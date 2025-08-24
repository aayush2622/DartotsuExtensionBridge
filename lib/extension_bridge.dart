import 'dart:io';

import 'package:dartotsu_extension_bridge/Settings/Settings.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'Aniyomi/AniyomiExtensions.dart';
import 'ExtensionManager.dart';
import 'package:objectbox/objectbox.dart';
import 'objectbox.g.dart';
import 'Mangayomi/MangayomiExtensions.dart';

late Store objectboxStore;
WebViewEnvironment? webViewEnvironment;

class DartotsuExtensionBridge {
  Future<void> init(Store? storeInstance, String dirName) async {
    var document = await getDatabaseDirectory(dirName);
    if (storeInstance == null) {
      objectboxStore = await openStore(
        directory: p.join(document.path, 'objectbox'),
      );
    } else {
      objectboxStore = storeInstance;
    }

    final bridgeSettingsBox = objectboxStore.box<BridgeSettings>();
    BridgeSettings? settings = bridgeSettingsBox.get(26);
    if (settings == null) {
      bridgeSettingsBox.put(BridgeSettings()..id = 26);
    }

    if (Platform.isAndroid) {
      Get.put(AniyomiExtensions(), tag: 'AniyomiExtensions');
    }
    Get.put(MangayomiExtensions(), tag: 'MangayomiExtensions');
    Get.put(ExtensionManager());
    if (Platform.isWindows) {
      final availableVersion = await WebViewEnvironment.getAvailableVersion();
      if (availableVersion != null) {
        webViewEnvironment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            userDataFolder: p.join(document.path, 'flutter_inappwebview'),
          ),
        );
      }
    }
  }
}

Future<Directory> getDatabaseDirectory(String dirName) async {
  final dir = await getApplicationDocumentsDirectory();
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    return dir;
  } else {
    String dbDir = p.join(dir.path, dirName, 'databases');
    await Directory(dbDir).create(recursive: true);
    return Directory(dbDir);
  }
}
