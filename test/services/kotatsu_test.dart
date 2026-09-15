import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Services/Kotatsu/KotatsuAndroid/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Services/Kotatsu/KotatsuDesktop/Models/Source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KotatsuSource', () {
    test('fromJson defaults itemType to manga and coerces the id', () {
      final s = KotatsuSource.fromJson({
        'id': 12345,
        'name': 'MangaDex',
        'baseUrl': 'https://mangadex.org',
        'lang': 'en',
        'jarName': 'plugin.jar',
        'pkgName': 'MANGADEX',
      });

      expect(s.id, '12345');
      expect(s.name, 'MangaDex');
      expect(s.itemType, ItemType.manga);
      expect(s.jarName, 'plugin.jar');
      expect(s.pkgName, 'MANGADEX');
    });

    test(
      'toJson round-trips jarName/pkgName alongside the base Source fields',
      () {
        final original = KotatsuSource(
          id: 'MANGADEX',
          name: 'MangaDex',
          baseUrl: 'https://mangadex.org',
          lang: 'en',
          jarName: 'plugin.jar',
          pkgName: 'MANGADEX',
          repo: 'https://example.com/parsers.jar',
        );

        final decoded = KotatsuSource.fromJson(original.toJson());

        expect(decoded.id, original.id);
        expect(decoded.name, original.name);
        expect(decoded.baseUrl, original.baseUrl);
        expect(decoded.jarName, original.jarName);
        expect(decoded.pkgName, original.pkgName);
        expect(decoded.repo, original.repo);
        expect(decoded.itemType, ItemType.manga);
      },
    );

    test('fromJson tolerates a missing jarName/pkgName', () {
      final s = KotatsuSource.fromJson({'id': 'X', 'name': 'X'});
      expect(s.jarName, isNull);
      expect(s.pkgName, isNull);
    });
  });

  group('KotatsuDesktopSource', () {
    test('fromJson defaults itemType to manga and coerces the id', () {
      final s = KotatsuDesktopSource.fromJson({
        'id': 12345,
        'name': 'MangaDex',
        'jarName': 'plugin.jar',
        'pkgName': 'MANGADEX',
      });

      expect(s.id, '12345');
      expect(s.itemType, ItemType.manga);
      expect(s.jarName, 'plugin.jar');
      expect(s.pkgName, 'MANGADEX');
    });

    test(
      'toJson round-trips jarName/pkgName alongside the base Source fields',
      () {
        final original = KotatsuDesktopSource(
          id: 'MANGADEX',
          name: 'MangaDex',
          jarName: 'plugin.jar',
          pkgName: 'MANGADEX',
          repo: 'https://example.com/parsers.jar',
        );

        final decoded = KotatsuDesktopSource.fromJson(original.toJson());

        expect(decoded.id, original.id);
        expect(decoded.jarName, original.jarName);
        expect(decoded.pkgName, original.pkgName);
        expect(decoded.repo, original.repo);
        expect(decoded.itemType, ItemType.manga);
      },
    );
  });
}
