import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';

import 'Services/Aniyomi/AniyomiExtensions.dart';

class test {
  static const platform = MethodChannel('aniyomiExtensionBridge');

  Future<void> testF() async {
    final extensionManager =
        Get.find<AniyomiExtensions>(tag: 'AniyomiExtensions');
    final extensions = await extensionManager.getInstalledAnimeExtensions(
      customPath: "/storage/emulated/0/Dartotsu",
    );
    for (var extension in extensions) {
      print('Name: ${extension.name}');
      print('Version: ${extension.apkName}');
      print('Is Obsolete: ${extension.isObsolete}');
      print('---');
    }
  }
}
