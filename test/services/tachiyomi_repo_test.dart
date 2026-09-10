import 'dart:convert';

import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Services/Shared/TachiyomiRepo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tachiyomiIndexUrl', () {
    test('appends index.min.json to a bare repo url', () {
      expect(
        tachiyomiIndexUrl('https://example.com/user/repo'),
        'https://example.com/user/repo/index.min.json',
      );
    });

    test('trims trailing slashes before appending', () {
      expect(
        tachiyomiIndexUrl('https://example.com/user/repo///'),
        'https://example.com/user/repo/index.min.json',
      );
    });

    test('is a no-op when the url already points at the index', () {
      const url = 'https://example.com/user/repo/index.min.json';
      expect(tachiyomiIndexUrl(url), url);
    });
  });

  group('tachiyomiFallbackRepoUrl', () {
    test('maps a github raw url to the jsdelivr mirror with branch', () {
      expect(
        tachiyomiFallbackRepoUrl(
          'https://raw.githubusercontent.com/owner/repo/master/index.min.json',
        ),
        'https://gcore.jsdelivr.net/gh/owner/repo@master',
      );
    });

    test('defaults the branch to main when absent', () {
      expect(
        tachiyomiFallbackRepoUrl(
          'https://raw.githubusercontent.com/owner/repo',
        ),
        'https://gcore.jsdelivr.net/gh/owner/repo@main',
      );
    });

    test('returns null when the path is too short', () {
      expect(tachiyomiFallbackRepoUrl('https://example.com/only'), isNull);
    });
  });

  group('parseTachiyomiRepoIndex', () {
    String body(List<Map<String, dynamic>> entries) => jsonEncode(entries);

    Source factory(TachiyomiRepoEntry e) => Source(
      id: e.id,
      name: e.name,
      lang: e.lang,
      version: e.version,
      isNsfw: e.isNsfw,
      itemType: e.itemType,
      repo: e.repo,
      iconUrl: e.iconUrl,
    );

    test('keeps only entries whose prefix maps to the target type', () {
      final result = parseTachiyomiRepoIndex<Source>(
        body: body([
          {
            'name': 'Aniyomi: Foo',
            'pkg': 'x.foo',
            'apk': 'foo.apk',
            'lang': 'en',
            'version': '1.0',
            'nsfw': 0,
            'sources': [
              {'id': '111'},
            ],
          },
          {
            'name': 'Tachiyomi: Bar',
            'pkg': 'x.bar',
            'sources': [
              {'id': '222'},
            ],
          },
          {'name': 'Unprefixed: Baz'},
        ]),
        repoUrl: 'https://host/o/r/index.min.json',
        targetType: ItemType.anime,
        prefixes: const {
          'Aniyomi: ': ItemType.anime,
          'Tachiyomi: ': ItemType.manga,
        },
        factory: factory,
      );

      expect(result, hasLength(1));
      expect(result.single.name, 'Foo'); // prefix stripped by its own length
      expect(result.single.id, '111');
      expect(result.single.lang, 'en');
      expect(result.single.itemType, ItemType.anime);
      expect(result.single.iconUrl, 'https://host/o/r/icon/x.foo.png');
    });

    test('strips a 9-char prefix without eating the first name char', () {
      // regression: IReader used substring(10) on "ireader: " (len 9)
      final result = parseTachiyomiRepoIndex<Source>(
        body: body([
          {
            'name': 'ireader: Noveler',
            'pkg': 'n.pkg',
            'sources': [
              {'id': 'a'},
            ],
          },
        ]),
        repoUrl: 'https://host/o/r/index.min.json',
        targetType: ItemType.novel,
        prefixes: const {'ireader: ': ItemType.novel},
        factory: factory,
      );

      expect(result.single.name, 'Noveler');
    });

    test('maps nsfw==1 to isNsfw and derives id from sources[0]', () {
      final result = parseTachiyomiRepoIndex<Source>(
        body: body([
          {
            'name': 'Aniyomi: N',
            'pkg': 'p',
            'nsfw': 1,
            'sources': [
              {'id': 42},
            ],
          },
        ]),
        repoUrl: 'https://host/o/r/index.min.json',
        targetType: ItemType.anime,
        prefixes: const {'Aniyomi: ': ItemType.anime},
        factory: factory,
      );

      expect(result.single.isNsfw, isTrue);
      expect(result.single.id, '42');
    });

    test('returns empty list for a non-array body instead of throwing', () {
      expect(
        parseTachiyomiRepoIndex<Source>(
          body: '{"not":"an array"}',
          repoUrl: 'r',
          targetType: ItemType.anime,
          prefixes: const {'Aniyomi: ': ItemType.anime},
          factory: factory,
        ),
        isEmpty,
      );
    });

    test('empty id when the entry has no sources', () {
      final result = parseTachiyomiRepoIndex<Source>(
        body: body([
          {'name': 'Aniyomi: NoSources', 'pkg': 'p'},
        ]),
        repoUrl: 'https://host/o/r/index.min.json',
        targetType: ItemType.anime,
        prefixes: const {'Aniyomi: ': ItemType.anime},
        factory: factory,
      );

      expect(result.single.id, '');
    });
  });
}
