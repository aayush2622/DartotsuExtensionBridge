import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../Engines/JavaEngine/Bridge/JavaBridge.dart';
import '../../../Engines/JavaEngine/Bridge/JavaBridgeFactory.dart';
import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Extensions/ExtensionSettings.dart';
import '../../../NetworkClient.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../../Shared/TachiyomiJavaDesktopExtension.dart';
import '../../Shared/TachiyomiRepo.dart';
import '../AniyomiSourceMethods.dart';
import 'Models/Source.dart';
import '../../../Network/NetworkSettingsSync.dart';

class AniyomiDesktopExtensions extends Extension
    with TachiyomiRepoBackend, TachiyomiJavaDesktopExtension {
  @override
  String get id => 'aniyomi_desktop';

  @override
  String get name => Platform.isIOS ? 'Aniyomi' : 'Aniyomi (Desktop)';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/aniyomi.svg";

  @override
  bool get supportsNovel => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    AdSource,
    (source) =>
        AniyomiSourceMethods(source as AdSource, JavaExtensionBridge(java)),
  );
  @override
  DownloadablePlugin plugin = AniyomiDesktopPlugin();

  @override
  final JavaBridge java = createJavaBridge();

  final _client = MClient.init();
  final _context = DartotsuExtensionBridge.context;

  @override
  http.Client get repoClient => _client;

  @override
  String get javaDataDir => 'aniyomi';

  @override
  List<Source> Function((Uint8List body, String repoUrl, ItemType type))
  get parseIndexIsolate => _parseExtensions;

  @override
  bool get refreshExtensionCountOnFetch => true;

  @override
  Future<bool> onInitialize() async {
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    unawaited(plugin.autoUpdate());

    final filePath = await plugin.getPath();

    await BridgeChannels.init();

    await java.init(pluginJarPath: filePath);

    var file = await _context.getDirectory(subPath: 'bridge/aniyomi');

    await java.call<void>("initializeDesktop", {"path": file!.path});

    await NetworkSettingsSync.register(
      this,
      (data) => java.call<void>('initClient', {'data': data}),
    );

    return true;
  }

  @override
  void dispose() async {
    super.dispose();
    NetworkSettingsSync.unregister(this);
    java.dispose();
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    await super.fetchInstalledAnimeExtensions();
    anime.installed.value = await _loadInstalled(
      'getInstalledAnimeExtensions',
      ItemType.anime,
    );
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    await super.fetchInstalledMangaExtensions();
    manga.installed.value = await _loadInstalled(
      'getInstalledMangaExtensions',
      ItemType.manga,
    );
  }

  @override
  Future<void> fetchAnimeExtensions() async {
    await super.fetchAnimeExtensions();
    anime.available.value = await fetchExtensions(ItemType.anime);
  }

  @override
  Future<void> fetchMangaExtensions() async {
    await super.fetchMangaExtensions();
    manga.available.value = await fetchExtensions(ItemType.manga);
  }

  Future<List<Source>> _loadInstalled(String method, ItemType type) =>
      loadInstalledJavaSources(method, type, AdSource.fromJson);

  @override
  Set<String> get schemes => {"aniyomi", "tachiyomi"};

  @override
  void handleSchemes(Uri uri) {}

  @override
  List<ExtensionSetting> settings(context) => [];
  static List<AdSource> _parseExtensions(
    (Uint8List body, String repoUrl, ItemType itemType) args,
  ) => parseTachiyomiIndexBytes<AdSource>(
    args.$1,
    args.$2,
    args.$3,
    prefixes: const {
      'Aniyomi: ': ItemType.anime,
      'Tachiyomi: ': ItemType.manga,
    },
    factory: _sourceFromEntry,
  );

  static AdSource _sourceFromEntry(TachiyomiRepoEntry e) => AdSource(
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

class AniyomiDesktopPlugin extends DownloadablePlugin {
  @override
  String get name => "aniyomiDesktop";

  @override
  String get fileName => "aniyomiDesktop-plugin.jar";
}
