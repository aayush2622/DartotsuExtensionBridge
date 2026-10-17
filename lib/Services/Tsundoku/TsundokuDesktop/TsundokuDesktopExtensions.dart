import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../Engines/JavaEngine/Bridge/JavaBridge.dart';
import '../../../Engines/JavaEngine/Bridge/JavaBridgeFactory.dart';
import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Extensions/ExtensionSettings.dart';
import '../../../Network/MClient.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Shared/JvmBackend.dart';
import '../../Shared/TachiyomiJavaDesktopExtension.dart';
import '../../Shared/TachiyomiRepo.dart';
import '../TsundokuSourceMethods.dart';
import 'Models/Source.dart';

class TsundokuDesktopExtensions extends Extension
    with JvmBackend, DesktopJvmBackend, TachiyomiRepoBackend, TachiyomiJavaDesktopExtension {
  @override
  String get id => 'tsundoku_desktop';

  @override
  String get name => Platform.isIOS ? 'Tsundoku' : 'Tsundoku (Desktop)';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/tsundoku.svg";

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    TdSource,
    (source) =>
        TsundokuSourceMethods(source as TdSource, JavaExtensionBridge(java)),
  );
  @override
  DownloadablePlugin plugin = TsundokuDesktopPlugin();

  @override
  final JavaBridge java = createJavaBridge();

  final _client = MClient.init();

  @override
  http.Client get repoClient => _client;

  @override
  String get javaDataDir => 'tsundoku';

  @override
  List<Source> Function((Uint8List body, String repoUrl, ItemType type))
  get parseIndexIsolate => _parseExtensions;

  @override
  bool get refreshExtensionCountOnFetch => true;



  @override
  Future<void> fetchInstalledNovelExtensions() async {
    await super.fetchInstalledNovelExtensions();

    novel.installed.value = await _loadInstalled(
      'getInstalledNovelExtensions',
      ItemType.novel,
    );
  }

  @override
  Future<void> fetchNovelExtensions() async {
    await super.fetchNovelExtensions();
    novel.available.value = await fetchExtensions(ItemType.novel);
  }

  Future<List<Source>> _loadInstalled(String method, ItemType type) =>
      loadInstalledJavaSources(method, type, TdSource.fromJson);

  @override
  Set<String> get schemes => {"tsundoku"};

  @override
  void handleSchemes(Uri uri) {}

  @override
  List<ExtensionSetting> settings(context) => [];
  static List<TdSource> _parseExtensions(
    (Uint8List body, String repoUrl, ItemType itemType) args,
  ) => parseTachiyomiIndexBytes<TdSource>(
    args.$1,
    args.$2,
    args.$3,
    prefixes: const {'Tsundoku: ': ItemType.novel},
    factory: _sourceFromEntry,
  );

  static TdSource _sourceFromEntry(TachiyomiRepoEntry e) => TdSource(
    id: e.id,
    name: e.name,
    pkgName: e.pkgName,
    apkName: e.apkName,
    lang: e.lang,
    version: e.version,
    isNsfw: e.isNsfw,
    itemType: e.itemType,
    repo: e.repo,
    iconUrl: e.iconUrl,
    apkUrlOverride: e.apkUrl,
    jarUrl: e.jarUrl,
  );
}

class TsundokuDesktopPlugin extends DownloadablePlugin {
  @override
  String get name => "tsundokuDesktop";

  @override
  String get fileName => "tsundokuDesktop-plugin.jar";
}
