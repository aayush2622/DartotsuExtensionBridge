import 'dart:io';

import 'package:get/get.dart';

import 'Aniyomi/AniyomiExtensions.dart';
import 'Aniyomi/AniyomiSourceMethods.dart';
import 'Extensions/Extensions.dart';
import 'Extensions/SourceMethods.dart';
import 'Mangayomi/MangayomiExtensions.dart';
import 'Mangayomi/MangayomiSourceMethods.dart';
import 'Models/Source.dart';
import 'extension_bridge.dart';
import 'Settings/Settings.dart';
import 'objectbox.g.dart';

final Box<BridgeSettings> bridgeSettingsBox = objectboxStore
    .box<BridgeSettings>();

class ExtensionManager extends GetxController {
  ExtensionManager() {
    initialize();
  }

  late final Rx<Extension> _currentManager;

  Extension get currentManager => _currentManager.value;

  void initialize() {
    final settings = bridgeSettingsBox.get(26)!;
    final savedType = ExtensionType.fromString(settings.currentManager);
    _currentManager = savedType.getManager().obs;
  }

  void setCurrentManager(ExtensionType type) {
    _currentManager.value = type.getManager();
    final settings = bridgeSettingsBox.get(26)!;
    settings.currentManager = type.toString();
    bridgeSettingsBox.put(settings);
  }
}

extension SourceMethodsExtension on Source {
  SourceMethods get methods => currentSourceMethods(this);
}

SourceMethods currentSourceMethods(Source source) {
  final type = source.extensionType;
  return type == ExtensionType.mangayomi
      ? MangayomiSourceMethods(source)
      : AniyomiSourceMethods(source);
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
