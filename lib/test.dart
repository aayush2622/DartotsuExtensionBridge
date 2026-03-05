import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';

import 'Services/Mangayomi/MangayomiExtensions.dart';
import 'dartotsu_extension_bridge.dart';

class test {
  static const platform = MethodChannel('aniyomiExtensionBridge');

  Future<void> testF() async {
    final extensionManager =
        Get.find<ExtensionManager>().get<MangayomiExtensions>();
    final extensions = await extensionManager.getInstalledAnimeExtensions();
    for (var extension in extensions) {
      print('Name: ${extension.name}');
      print('---');
    }
  }
}
