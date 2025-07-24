import 'dart:io';

import 'package:dartotsu_extension_bridge/Settings/Settings.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:isar/isar.dart';

import 'Mangayomi/Eval/dart/model/source_preference.dart';
import 'Mangayomi/Models/Source.dart';

late Isar isar;
WebViewEnvironment? webViewEnvironment;

class DartotsuExtensionBridge {
  /// 🛠️ Isar Setup Guide:
  ///
  /// 📦 Make sure to include the following models in your Isar schema:
  ///
  ///
  /// import 'package:dartotsu_extension_bridge/Mangayomi/Eval/dart/model/source_preference.dart';
  /// import 'package:dartotsu_extension_bridge/Mangayomi/Models/Source.dart';
  /// import 'package:dartotsu_extension_bridge/Settings/Settings.dart';
  ///
  /// 🧩 Add these models when opening your Isar instance:
  ///
  ///
  /// Isar.open([
  ///   MSourceSchema,
  //    SourcePreferenceSchema,
  //    SourcePreferenceStringValueSchema,
  //    BridgeSettingsSchema,
  /// ]);
  ///
  ///
  /// 🚀 Then pass the initialized `isar` instance to init method
  Future<void> init(Isar? isarInstance) async {
    var document = await getApplicationDocumentsDirectory();
    if (isarInstance == null) {
      isar = Isar.openSync(
        [
          MSourceSchema,
          SourcePreferenceSchema,
          SourcePreferenceStringValueSchema,
          BridgeSettingsSchema,
        ],
        directory: p.join(document.path, 'isar'),
      ); //may crash app if directory does not exist, have to test
    } else {
      isar = isarInstance;
    }
    final settings = await isar.bridgeSettings
        .filter()
        .idEqualTo(26)
        .findFirst();
    if (settings == null) {
      isar.writeTxnSync(
        () => isar.bridgeSettings.putSync(BridgeSettings()..id = 26),
      );
    }
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

  /*  Future<void> fetchAnimeTitles() async {
    var extensions = await AniyomiExtensions().init();
    var ext = extensions.installedAnimeExtensions.value[0];
    var media = await AniyomiSourceMethods(ext).getLatestUpdates(1);
    print(media.list.first.title);
    var data = await AniyomiSourceMethods(ext).getDetail(media.list.first);
    print(data.url);
    var quality = await AniyomiSourceMethods(
      ext,
    ).getVideoList(data.episodes!.first);
    print(quality.first.toJson());
  }*/
}
