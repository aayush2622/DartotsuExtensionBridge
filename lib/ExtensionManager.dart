import 'dart:io';

import 'package:get/get.dart';

import 'Aniyomi/AniyomiExtensions.dart';
import 'Extensions/Extensions.dart';
import 'Mangayomi/MangayomiExtensions.dart';

class ExtensionManager extends GetxController {
  static final ExtensionManager _instance = ExtensionManager._internal();

  factory ExtensionManager() => _instance;

  ExtensionManager._internal();

  final Rx<Extension> _currentManager =
      getSupportedExtensions.first.manager.obs;

  Extension get currentManager => _currentManager.value;

  void setCurrentManager(ExtensionType type) {
    _currentManager.value = type.manager;
    update();
  }
}

List<ExtensionType> get getSupportedExtensions {
  if (Platform.isAndroid) {
    return [ExtensionType.mangayomi, ExtensionType.aniyomi];
  } else {
    return [ExtensionType.mangayomi];
  }
}

enum ExtensionType {
  aniyomi,
  mangayomi;

  Extension get manager {
    switch (this) {
      case ExtensionType.aniyomi:
        return Get.put(AniyomiExtensions(), tag: 'aniyomi');
      case ExtensionType.mangayomi:
        return Get.put(MangayomiExtensions(), tag: 'mangayomi');
    }
  }
}
