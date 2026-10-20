import 'dart:convert';

import 'package:dartotsu_extension_bridge/Extensions/RepoGuard.dart';
import 'package:dartotsu_extension_bridge/Services/Shared/TachiyomiRepo.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> json(Object value) => utf8.encode(jsonEncode(value));

void main() {
  group('normalizeRepoUrl', () {
    test('trims, drops quotes and trailing slashes', () {
      expect(
        normalizeRepoUrl('  "https://example.com/repo//"  '),
        'https://example.com/repo',
      );
    });

    test('adds https to a bare host', () {
      expect(
        normalizeRepoUrl('example.com/repo/index.min.json'),
        'https://example.com/repo/index.min.json',
      );
    });

    test('turns a GitHub file page into its raw file', () {
      expect(
        normalizeRepoUrl('https://github.com/owner/repo/blob/main/dir/repo.json'),
        'https://raw.githubusercontent.com/owner/repo/main/dir/repo.json',
      );
    });

    test('rejects what is not an http link', () {
      expect(() => normalizeRepoUrl(''), throwsA(isA<RepoException>()));
      expect(() => normalizeRepoUrl('hello'), throwsA(isA<RepoException>()));
      expect(
        () => normalizeRepoUrl('ftp://example.com/repo'),
        throwsA(isA<RepoException>()),
      );
    });
  });

  group('detectRepoFormat', () {
    test('tachiyomi and IReader indexes', () {
      expect(
        detectRepoFormat(json([
          {'pkg': 'eu.kanade.tachiyomi.extension.en.x', 'apk': 'x.apk'},
        ])),
        RepoFormat.tachiyomi,
      );
      expect(
        detectRepoFormat(json([
          {'pkg': 'ireader.x.en', 'apk': 'x.apk'},
        ])),
        RepoFormat.iReader,
      );
    });

    test('CloudStream plugin lists and manifests', () {
      expect(
        detectRepoFormat(json([
          {'internalName': 'X', 'url': 'https://h/x.cs3'},
        ])),
        RepoFormat.cloudStream,
      );
      expect(
        detectRepoFormat(json({
          'name': 'Repo',
          'pluginLists': ['https://h/plugins.json'],
        })),
        RepoFormat.cloudStream,
      );
    });

    test('the JSON source lists', () {
      expect(
        detectRepoFormat(json([
          {'name': 'X', 'sourceCodeUrl': 'https://h/x.js'},
        ])),
        RepoFormat.mangayomi,
      );
      expect(
        detectRepoFormat(json({'sourceName': 'X', 'scriptUrl': 'https://h'})),
        RepoFormat.sora,
      );
      expect(
        detectRepoFormat(json([
          {'site': 'https://s', 'url': 'https://h/x.js'},
        ])),
        RepoFormat.lnReader,
      );
      expect(
        detectRepoFormat(json([
          {'bookSourceUrl': 'https://s'},
        ])),
        RepoFormat.legado,
      );
      expect(
        detectRepoFormat(json({
          'sources': [
            {'downloadURL': 'x.aix'},
          ],
        })),
        RepoFormat.aidoku,
      );
    });

    test('binary indexes', () {
      expect(detectRepoFormat([0x50, 0x4b, 0x03, 0x04, 0]), RepoFormat.kotatsu);
      expect(detectRepoFormat([0x1f, 0x8b, 0x08]), RepoFormat.tachiyomi);
    });

    test('unknown content', () {
      expect(detectRepoFormat(utf8.encode('not json')), isNull);
      expect(detectRepoFormat(json({'hello': 'world'})), isNull);
    });
  });

  test('looksLikeWebPage', () {
    expect(looksLikeWebPage(utf8.encode('<!DOCTYPE html><html>')), isTrue);
    expect(looksLikeWebPage(utf8.encode('  <html lang="en">')), isTrue);
    expect(looksLikeWebPage(json([])), isFalse);
  });

  group('repo.json links', () {
    test('a repo.json link points at the index in the same folder', () {
      expect(
        tachiyomiIndexCandidates(
          'https://raw.githubusercontent.com/yuzono/manga-repo/repo/repo.json',
        ),
        [
          'https://raw.githubusercontent.com/yuzono/manga-repo/repo/index.pb',
          'https://raw.githubusercontent.com/yuzono/manga-repo/repo/index.min.json',
        ],
      );
    });

    test('a github blob link to repo.json becomes the same folder', () {
      final raw = normalizeRepoUrl(
        'https://github.com/keiyoushi/extensions/blob/repo/repo.json',
      );
      expect(
        tachiyomiIndexCandidates(raw).last,
        'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
      );
      expect(
        tachiyomiIndexUrl(raw),
        'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
      );
    });
  });

  group('tachiyomiIndexCandidates', () {
    test('tries index.pb before index.min.json for a base URL', () {
      expect(tachiyomiIndexCandidates('https://h/repo/'), [
        'https://h/repo/index.pb',
        'https://h/repo/index.min.json',
      ]);
    });

    test('keeps an explicit index file', () {
      expect(tachiyomiIndexCandidates('https://h/repo/index.min.json'), [
        'https://h/repo/index.min.json',
      ]);
      expect(tachiyomiIndexCandidates('https://h/repo/index.pb'), [
        'https://h/repo/index.pb',
      ]);
    });
  });
}
