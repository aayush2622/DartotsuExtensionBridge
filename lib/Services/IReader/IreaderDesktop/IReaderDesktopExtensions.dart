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
import '../IReaderSourceMethods.dart';
import 'Models/Source.dart';

class IReaderDesktopExtensions extends Extension
    with JvmBackend, DesktopJvmBackend, TachiyomiRepoBackend, TachiyomiJavaDesktopExtension {
  @override
  Set<RepoFormat> get repoFormats => const {RepoFormat.iReader};

  @override
  String get id => 'ireader_desktop';

  @override
  String get name => Platform.isIOS ? 'Ireader' : 'Ireader (Desktop)';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/ireader.svg";

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    IdSource,
    (source) =>
        IReaderSourceMethods(source as IdSource, JavaExtensionBridge(java)),
  );
  @override
  DownloadablePlugin plugin = IreaderDesktopPlugin();

  @override
  final JavaBridge java = createJavaBridge();

  final _client = MClient.init();

  @override
  http.Client get repoClient => _client;

  @override
  String get javaDataDir => 'ireader';

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
      loadInstalledJavaSources(method, type, IdSource.fromJson);

  @override
  Set<String> get schemes => {"ireader"};

  @override
  void handleSchemes(Uri uri) {}

  @override
  List<ExtensionSetting> settings(context) => [];

  static List<IdSource> _parseExtensions(
    (Uint8List body, String repoUrl, ItemType itemType) args,
  ) => parseTachiyomiIndexBytes<IdSource>(
    args.$1,
    args.$2,
    args.$3,
    prefixes: const {'ireader: ': ItemType.novel},
    factory: _sourceFromEntry,
  );

  static IdSource _sourceFromEntry(TachiyomiRepoEntry e) => IdSource(
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

class IreaderDesktopPlugin extends DownloadablePlugin {
  @override
  String get name => "ireaderDesktop";

  @override
  String get fileName => "ireaderDesktop-plugin.jar";
}
