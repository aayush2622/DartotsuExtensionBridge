import 'dart:io';

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
  ///
  ///
  /// 🧩 Add these models when opening your Isar instance:
  ///
  ///
  /// Isar.open([
  ///   MSourceSchema,
  //    SourcePreferenceSchema,
  //    SourcePreferenceStringValueSchema,
  /// ]);
  ///
  ///
  /// 🚀 Then pass the initialized `isar` instance to init method
  Future<void> init(Isar? isarInstance) async {
    if (isarInstance == null) {
      isar = Isar.openSync([
        MSourceSchema,
        SourcePreferenceSchema,
        SourcePreferenceStringValueSchema,
      ], directory: (await getApplicationDocumentsDirectory()).path);
    } else {
      isar = isarInstance;
    }
    if (Platform.isWindows) {
      final availableVersion = await WebViewEnvironment.getAvailableVersion();
      if (availableVersion != null) {
        final document = await getApplicationDocumentsDirectory();
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
