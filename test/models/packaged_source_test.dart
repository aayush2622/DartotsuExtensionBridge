import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Services/Aniyomi/AniyomiDesktop/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Services/IReader/IreaderAndroid/Models/Source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PackagedSource.apkUrl', () {
    test('prefers an explicit override', () {
      final s = AdSource(
        apkUrlOverride: 'https://host/o/r/apk/x-v1.apk',
        apkName: 'ignored.apk',
        iconUrl: 'https://host/o/r/icon/x.png',
      );
      expect(s.apkUrl, 'https://host/o/r/apk/x-v1.apk');
    });

    test('derives from the repo layout via iconUrl + apkName', () {
      final s = AdSource(
        apkName: 'tachiyomi-x.foo-v9.apk',
        iconUrl: 'https://host/o/r/icon/x.foo.png',
      );
      expect(s.apkUrl, 'https://host/o/r/apk/tachiyomi-x.foo-v9.apk');
    });

    test('is null without an apkName or iconUrl', () {
      expect(AdSource(iconUrl: 'https://h/icon/a.png').apkUrl, isNull);
      expect(AdSource(apkName: 'a.apk').apkUrl, isNull);
    });

    test('empty override falls through to derivation', () {
      final s = AdSource(
        apkUrlOverride: '',
        apkName: 'a.apk',
        iconUrl: 'https://h/r/icon/p.png',
      );
      expect(s.apkUrl, 'https://h/r/apk/a.apk');
    });

    test('ISource reads a legacy stored apkUrl as the override', () {
      final s = ISource.fromJson({
        'name': 'X',
        'apkUrl': 'https://legacy/x.apk',
        'itemType': ItemType.novel.index,
      });
      expect(s.apkUrlOverride, 'https://legacy/x.apk');
      expect(s.apkUrl, 'https://legacy/x.apk');
    });
  });
}
