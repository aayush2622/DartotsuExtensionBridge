import 'dart:convert';

import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Services/LnReader/Manifest.dart';
import 'package:dartotsu_extension_bridge/Services/LnReader/Models/Source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLnReaderManifest', () {
    const repo =
        'https://raw.githubusercontent.com/LNReader/lnreader-plugins/'
        'plugins/v3.0.0/.dist/plugins.min.json';

    test('maps every documented field from a plugins.min.json entry', () {
      final sources = parseLnReaderManifest(
        jsonEncode([
          {
            'id': 'arnovel',
            'name': 'ArNovel',
            'site': 'https://ar-no.com/',
            'lang': 'العربية',
            'version': '2.2.0',
            'url': 'https://host/.js/src/plugins/arabic/ArNovel.js',
            'iconUrl': 'https://host/static/arnovel/icon.png',
          },
        ]),
        repo,
      ).cast<LSource>();

      expect(sources, hasLength(1));
      final s = sources.single;
      expect(s.id, 'arnovel');
      expect(s.name, 'ArNovel');
      expect(s.baseUrl, 'https://ar-no.com/');
      expect(s.lang, 'العربية');
      expect(s.version, '2.2.0');
      expect(s.versionLast, '2.2.0');
      expect(s.iconUrl, 'https://host/static/arnovel/icon.png');
      expect(s.sourceCodeUrl, 'https://host/.js/src/plugins/arabic/ArNovel.js');
      expect(s.itemType, ItemType.novel);
      expect(s.repo, repo);
      expect(s.customCssUrl, isNull);
    });

    test('keeps the optional customCSS url', () {
      final s = parseLnReaderManifest(
        jsonEncode([
          {
            'id': 'x',
            'name': 'X',
            'version': '1.0.0',
            'url': 'https://host/x.js',
            'customCSS': 'https://host/x.css',
          },
        ]),
        repo,
      ).cast<LSource>().single;
      expect(s.customCssUrl, 'https://host/x.css');
    });

    test('skips entries without a plugin url', () {
      final sources = parseLnReaderManifest(
        jsonEncode([
          {'id': 'a', 'name': 'A', 'version': '1.0.0'},
          {'id': 'b', 'name': 'B', 'version': '1.0.0', 'url': 'https://h/b.js'},
        ]),
        repo,
      );
      expect(sources.map((e) => e.id), ['b']);
    });

    test('defaults a missing version to 1.0.0', () {
      final s = parseLnReaderManifest(
        jsonEncode([
          {'id': 'x', 'name': 'X', 'url': 'https://h/x.js'},
        ]),
        repo,
      ).single;
      expect(s.version, '1.0.0');
    });

    test('returns empty for a non-array / junk body instead of throwing', () {
      expect(parseLnReaderManifest('{"not":"array"}', repo), isEmpty);
      expect(parseLnReaderManifest('not json', repo), isEmpty);
    });

    test('LSource survives a JSON round-trip', () {
      final s = parseLnReaderManifest(
        jsonEncode([
          {'id': 'x', 'name': 'X', 'version': '1.2.3', 'url': 'https://h/x.js'},
        ]),
        repo,
      ).cast<LSource>().single..sourceCode = 'export default {};';

      final back = LSource.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back.id, 'x');
      expect(back.sourceCode, 'export default {};');
      expect(back.sourceCodeUrl, 'https://h/x.js');
      expect(back.itemType, ItemType.novel);
    });
  });
}
