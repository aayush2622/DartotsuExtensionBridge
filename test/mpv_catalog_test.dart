import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:dartotsu_extension_bridge/Engines/Mpv/MpvAddon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the download catalog matches the build hook bundles', () {
    final json =
        jsonDecode(
              File('hook/native_bundles.json')
                  .readAsStringSync(),
            )['bundles']
            as Map<String, dynamic>;
    const keys = {
      'android_arm64': Abi.androidArm64,
      'android_arm': Abi.androidArm,
      'android_x64': Abi.androidX64,
      'android_ia32': Abi.androidIA32,
      'windows_arm64': Abi.windowsArm64,
      'windows_x64': Abi.windowsX64,
      'linux_x64': Abi.linuxX64,
      'linux_arm64': Abi.linuxArm64,
    };
    expect(MpvAddon.catalog.keys.toSet(), keys.values.toSet());
    keys.forEach((key, abi) {
      final expected = json[key] as Map<String, dynamic>;
      final actual = MpvAddon.catalog[abi]!;
      expect(actual.url, expected['url'], reason: key);
      expect(actual.sha256, expected['sha256'], reason: key);
      expect(actual.library, expected['library'], reason: key);
      expect(actual.root, expected['root'] ?? '', reason: key);
      expect(actual.sevenZip, expected['format'] == '7z', reason: key);
    });
  });
}
