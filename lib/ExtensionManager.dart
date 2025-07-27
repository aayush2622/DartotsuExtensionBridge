import 'dart:io';

import 'package:get/get.dart';

import 'Aniyomi/AniyomiExtensions.dart';
import 'Mangayomi/MangayomiExtensions.dart';
import 'dartotsu_extension_bridge.dart';

class ExtensionManager extends GetxController {
  ExtensionManager() {
    initialize();
  }

  late final Rx<Extension> _currentManager;

  Extension get currentManager => _currentManager.value;

  void initialize() {
    final settings = isar.bridgeSettings.getSync(26)!;
    final savedType = ExtensionType.fromString(settings.currentManager);
    _currentManager = savedType.getManager().obs;
  }

  void setCurrentManager(ExtensionType type) {
    _currentManager.value = type.getManager();
    final settings = isar.bridgeSettings.getSync(26)!;
    isar.writeTxnSync(() {
      isar.bridgeSettings.putSync(settings..currentManager = type.toString());
    });
  }
}

List<ExtensionType> get getSupportedExtensions =>
    Platform.isAndroid ? ExtensionType.values : [ExtensionType.mangayomi];

enum ExtensionType {
  mangayomi,
  aniyomi;

  Extension getManager() {
    switch (this) {
      case ExtensionType.aniyomi:
        return Get.find<AniyomiExtensions>(tag: 'AniyomiExtensions');
      case ExtensionType.mangayomi:
        return Get.find<MangayomiExtensions>(tag: 'MangayomiExtensions');
    }
  }

  @override
  String toString() {
    switch (this) {
      case ExtensionType.aniyomi:
        return 'Aniyomi';
      case ExtensionType.mangayomi:
        return 'Mangayomi';
    }
  }

  static ExtensionType fromString(String? name) {
    return ExtensionType.values.firstWhere(
      (e) => e.toString() == name,
      orElse: () => getSupportedExtensions.first,
    );
  }

  static ExtensionType fromManager(Extension manager) {
    if (manager is AniyomiExtensions) {
      return ExtensionType.aniyomi;
    } else if (manager is MangayomiExtensions) {
      return ExtensionType.mangayomi;
    }
    throw Exception('Unknown extension manager type');
  }
}
