import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Services/IReader/IReaderIcons.dart';
import 'package:dartotsu_extension_bridge/Services/IReader/IreaderDesktop/Models/Source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('icons match the apk name without its version', () {
    final icons = ireaderIconsByStem([
      'ireader-en-allnovelfull-v2.3.png',
      'ireader-ar-armtl-v2.2.png',
      'readme.md',
    ]);
    final full = IdSource(
      id: '1',
      name: 'AllNovelFull',
      apkName: 'ireader-en-allnovelfull-v2.1.apk',
      itemType: ItemType.novel,
    );
    final none = IdSource(
      id: '2',
      name: 'AllNovel',
      apkName: 'ireader-en-allnovel-v2.1.apk',
      itemType: ItemType.novel,
      iconUrl: 'keep',
    );
    applyIreaderIcons([full, none], icons, 'https://host/repo');
    expect(full.iconUrl, 'https://host/repo/icon/ireader-en-allnovelfull-v2.3.png');
    expect(none.iconUrl, 'keep');
  });
}
