import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Services/Shared/ProtoReader.dart';
import 'package:dartotsu_extension_bridge/Services/Shared/TachiyomiRepo.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Tiny protobuf encoder, just enough to build index.pb fixtures.
// ---------------------------------------------------------------------------

List<int> _varint(int value) {
  final out = <int>[];
  var v = value;
  while (true) {
    final b = v & 0x7f;
    v >>= 7;
    if (v == 0) {
      out.add(b);
      return out;
    }
    out.add(b | 0x80);
  }
}

List<int> _tag(int field, int wire) => _varint((field << 3) | wire);

List<int> pInt(int field, int value) => [..._tag(field, 0), ..._varint(value)];

List<int> pBytes(int field, List<int> body) => [
  ..._tag(field, 2),
  ..._varint(body.length),
  ...body,
];

List<int> pStr(int field, String value) => pBytes(field, utf8.encode(value));

/// Builds the `resources` submessage (apk, icon, and keiyoushi's jar at 501).
List<int> resources({required String apk, required String icon, String? jar}) =>
    [...pStr(1, apk), ...pStr(2, icon), if (jar != null) ...pStr(501, jar)];

List<int> source({
  required int id,
  required String name,
  required String language,
  String homeUrl = '',
}) => [
  ...pInt(1, id),
  ...pStr(2, name),
  ...pStr(3, language),
  if (homeUrl.isNotEmpty) ...pStr(4, homeUrl),
];

List<int> extension({
  required String name,
  required String pkg,
  required List<int> res,
  String lib = '1.6',
  int versionCode = 1,
  String versionName = '1.0.0',
  int contentWarning = 1,
  List<List<int>> sources = const [],
}) => [
  ...pStr(1, name),
  ...pStr(2, pkg),
  ...pBytes(3, res),
  ...pStr(4, lib),
  ...pInt(5, versionCode),
  ...pStr(6, versionName),
  ...pInt(7, contentWarning),
  for (final s in sources) ...pBytes(8, s),
];

/// Top-level store message, optionally gzipped like the real index.pb.
Uint8List store({
  required List<List<int>> extensions,
  String name = 'Keiyoushi',
  String badge = 'KEI',
  String? extensionListUrl,
  bool gzipped = true,
}) {
  final list = <int>[for (final e in extensions) ...pBytes(1, e)];
  final body = <int>[
    ...pStr(1, name),
    ...pStr(2, badge),
    ...pStr(3, 'deadbeef'),
    ...pBytes(4, [...pStr(1, 'https://example.org')]),
    if (extensionListUrl == null) ...pBytes(101, list),
    if (extensionListUrl != null) ...pStr(102, extensionListUrl),
  ];
  return Uint8List.fromList(gzipped ? gzip.encode(body) : body);
}

Source _factory(TachiyomiRepoEntry e) => Source(
  id: e.id,
  name: e.name,
  lang: e.lang,
  version: e.version,
  isNsfw: e.isNsfw,
  itemType: e.itemType,
  repo: e.repo,
  iconUrl: e.iconUrl,
);

void main() {
  group('ProtoMessage', () {
    test('decodes varints, strings and nested messages', () {
      final bytes = Uint8List.fromList([
        ...pInt(1, 300),
        ...pStr(2, 'hello'),
        ...pBytes(3, [...pStr(1, 'inner')]),
      ]);

      final msg = ProtoMessage.decode(bytes);

      expect(msg.readInt(1), 300);
      expect(msg.readString(2), 'hello');
      expect(msg.readMessage(3)?.readString(1), 'inner');
      expect(msg.has(4), isFalse);
      expect(msg.readInt(4), isNull);
    });

    test('keeps every value of a repeated field', () {
      final bytes = Uint8List.fromList([
        ...pStr(1, 'a'),
        ...pStr(1, 'b'),
        ...pStr(1, 'c'),
      ]);

      expect(ProtoMessage.decode(bytes).readStrings(1), ['a', 'b', 'c']);
    });

    test('truncated input degrades to the fields read so far', () {
      final full = Uint8List.fromList([...pStr(1, 'kept'), ...pStr(2, 'lost')]);
      final truncated = Uint8List.sublistView(full, 0, full.length - 2);

      expect(ProtoMessage.decode(truncated).readString(1), 'kept');
    });
  });

  group('index format detection', () {
    test('tachiyomiIndexFormat picks protobuf only for .pb', () {
      expect(
        tachiyomiIndexFormat('https://host/repo/index.pb'),
        RepoIndexFormat.protobuf,
      );
      expect(
        tachiyomiIndexFormat('https://host/repo/index.min.json'),
        RepoIndexFormat.json,
      );
      expect(tachiyomiIndexFormat('https://host/repo'), RepoIndexFormat.json);
    });

    test('tachiyomiIndexUrl leaves a .pb endpoint alone', () {
      const pb = 'https://github.com/keiyoushi/extensions/raw/repo/index.pb';
      expect(tachiyomiIndexUrl(pb), pb);
    });

    test('tachiyomiIndexUrl still appends the json index otherwise', () {
      expect(
        tachiyomiIndexUrl('https://host/repo/'),
        'https://host/repo/index.min.json',
      );
    });
  });

  group('parseTachiyomiPbIndex', () {
    const repoUrl = 'https://host/repo/index.pb';

    test('parses a gzipped store and maps every documented field', () {
      final body = store(
        extensions: [
          extension(
            name: 'AHottie',
            pkg: 'eu.kanade.tachiyomi.extension.all.ahottie',
            res: resources(
              apk: 'https://host/dl/tachiyomi-all.ahottie-v1.6.4.apk',
              icon: 'https://host/icon/ahottie.png',
              jar: 'https://host/dl/tachiyomi-all.ahottie-v1.6.4.jar',
            ),
            versionName: '1.6.4',
            contentWarning: 3, // NSFW
            sources: [source(id: 42, name: 'AHottie', language: 'en')],
          ),
        ],
      );

      final result = parseTachiyomiPbIndex<Source>(
        body: body,
        repoUrl: repoUrl,
        targetType: ItemType.manga,
        factory: _factory,
      );

      expect(result, hasLength(1));
      final s = result.single;
      expect(s.name, 'AHottie');
      expect(s.id, '42');
      expect(s.lang, 'en');
      expect(s.version, '1.6.4');
      expect(s.isNsfw, isTrue);
      expect(s.itemType, ItemType.manga);
      expect(s.iconUrl, 'https://host/icon/ahottie.png');
      expect(s.repo, repoUrl);
    });

    test('works on an uncompressed store too', () {
      final body = store(
        gzipped: false,
        extensions: [
          extension(
            name: 'Plain',
            pkg: 'eu.kanade.tachiyomi.extension.en.plain',
            res: resources(apk: 'a.apk', icon: 'i.png'),
            sources: [source(id: 1, name: 'Plain', language: 'en')],
          ),
        ],
      );

      expect(
        parseTachiyomiPbIndex<Source>(
          body: body,
          repoUrl: repoUrl,
          targetType: ItemType.manga,
          factory: _factory,
        ),
        hasLength(1),
      );
    });

    test('contentWarning SAFE/UNSPECIFIED are not nsfw, MIXED is', () {
      List<Source> parseWith(int warning) => parseTachiyomiPbIndex<Source>(
        body: store(
          extensions: [
            extension(
              name: 'X',
              pkg: 'eu.kanade.tachiyomi.extension.en.x',
              res: resources(apk: 'a.apk', icon: 'i.png'),
              contentWarning: warning,
              sources: [source(id: 1, name: 'X', language: 'en')],
            ),
          ],
        ),
        repoUrl: repoUrl,
        targetType: ItemType.manga,
        factory: _factory,
      );

      expect(parseWith(0).single.isNsfw, isFalse); // UNSPECIFIED
      expect(parseWith(1).single.isNsfw, isFalse); // SAFE
      expect(parseWith(2).single.isNsfw, isTrue); // MIXED
      expect(parseWith(3).single.isNsfw, isTrue); // NSFW
    });

    test('multi-language extensions collapse to "all"', () {
      final result = parseTachiyomiPbIndex<Source>(
        body: store(
          extensions: [
            extension(
              name: 'Multi',
              pkg: 'eu.kanade.tachiyomi.extension.all.multi',
              res: resources(apk: 'a.apk', icon: 'i.png'),
              sources: [
                source(id: 1, name: 'Multi', language: 'en'),
                source(id: 2, name: 'Multi', language: 'id'),
              ],
            ),
          ],
        ),
        repoUrl: repoUrl,
        targetType: ItemType.manga,
        factory: _factory,
      );

      expect(result.single.lang, 'all');
      expect(result.single.id, '1'); // first source wins
    });

    test('item type comes from the package name, filtering the rest out', () {
      final body = store(
        extensions: [
          extension(
            name: 'Manga',
            pkg: 'eu.kanade.tachiyomi.extension.en.manga',
            res: resources(apk: 'a.apk', icon: 'i.png'),
            sources: [source(id: 1, name: 'Manga', language: 'en')],
          ),
          extension(
            name: 'Anime',
            pkg: 'eu.kanade.tachiyomi.animeextension.en.anime',
            res: resources(apk: 'b.apk', icon: 'i.png'),
            sources: [source(id: 2, name: 'Anime', language: 'en')],
          ),
        ],
      );

      final manga = parseTachiyomiPbIndex<Source>(
        body: body,
        repoUrl: repoUrl,
        targetType: ItemType.manga,
        factory: _factory,
      );
      final anime = parseTachiyomiPbIndex<Source>(
        body: body,
        repoUrl: repoUrl,
        targetType: ItemType.anime,
        factory: _factory,
      );

      expect(manga.map((e) => e.name), ['Manga']);
      expect(anime.map((e) => e.name), ['Anime']);
    });

    test('returns empty rather than throwing on junk input', () {
      expect(
        parseTachiyomiPbIndex<Source>(
          body: Uint8List.fromList([0, 1, 2, 3]),
          repoUrl: repoUrl,
          targetType: ItemType.manga,
          factory: _factory,
        ),
        isEmpty,
      );
    });
  });

  group('tachiyomiPbExtensionListUrl', () {
    test('returns the redirect url when the list is not inlined', () {
      final body = store(
        extensions: const [],
        extensionListUrl: 'https://host/repo/extensions.pb',
      );
      expect(
        tachiyomiPbExtensionListUrl(body),
        'https://host/repo/extensions.pb',
      );
    });

    test('returns null when the list is inlined', () {
      final body = store(
        extensions: [
          extension(
            name: 'X',
            pkg: 'eu.kanade.tachiyomi.extension.en.x',
            res: resources(apk: 'a.apk', icon: 'i.png'),
          ),
        ],
      );
      expect(tachiyomiPbExtensionListUrl(body), isNull);
    });
  });
}
