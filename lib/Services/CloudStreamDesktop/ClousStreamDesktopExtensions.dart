import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../Engines/JavaEngine/Bridge/JniBridge.dart';
import '../../Engines/JavaEngine/Bridge/SidecarBridge.dart';
import '../../ExtensionBridge.dart';
import '../../Extensions/DownloadablePlugin.dart';
import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../NetworkClient.dart';
import '../../Settings/KvStore.dart';
import '../Network.dart';
import 'CloudStreamService.dart';
import 'ClousStreamDesktopSourceMethods.dart';

class CloudStreamDesktopExtensions extends Extension {
  @override
  String get name => 'CloudStream (Desktop)';

  @override
  String get id => 'cloudstream_desktop';

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    CloudStreamSourceMethodsDesktop,
    (source) => CloudStreamSourceMethodsDesktop(source, jni),
  );

  @override
  Future<void> addRepo(String repoUrl, ItemType type) {
    throw UnimplementedError();
  }

  @override
  DownloadablePlugin plugin = CloudStreamDesktopPlugin();

  final JavaBridge jni = (() {
    final useSidecar = getVal("cloudStreamDesktopUseSidecar") ?? false;

    final bridge = Platform.isMacOS || useSidecar
        ? SidecarBridge()
        : JniBridge();

    Logger.log("Using ${bridge.runtimeType}");
    return bridge;
  })();

  final _client = MClient.init();

  final _context = DartotsuExtensionBridge.context;

  @override
  Future<bool> onInitialize() async {
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    unawaited(plugin.autoUpdate());

    final filePath = await plugin.getPath();

    await BridgeChannels.init();

    await jni.init(pluginJarPath: filePath, handler: CloudStreamService());

    var file = await _context.getDirectory(subPath: 'bridge/aniyomi');

    await jni.call<void>("initializeDesktop", {"path": file!.path});

    if (_context.network != null) {
      await jni.call<void>("initClient", {
        "data": jsonEncode({
          "dns": _context.network?.dns,
          "proxy": _context.network?.proxy,
        }),
      });
    }

    return true;
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    await super.fetchInstalledAnimeExtensions();
    getInstalledRx(ItemType.anime).value = await _loadInstalled(
      "getInstalledAnimeExtensions",
      ItemType.anime,
    );
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    await super.fetchInstalledMangaExtensions();
    getInstalledRx(ItemType.manga).value = await _loadInstalled(
      "getInstalledMangaExtensions",
      ItemType.manga,
    );
  }

  Future<List<Source>> _loadInstalled(String method, ItemType type) async {
    try {
      final dir = await DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/cloudStream/extensions/${type.toString()}',
        useSystemPath: false,
        useCustomPath: true,
      );

      final result = await jni.call<List<Map<String, dynamic>>>(method, {
        "path": dir!.path,
      });

      return result
          .map((e) => Source.fromJson(e))
          .where((s) => s.itemType == type)
          .toList(growable: false);
    } catch (e, s) {
      Logger.log("Desktop loadInstalled error: $e\n$s");
      return [];
    }
  }

  @override
  Future<void> installSource(Source source) {
    // TODO: implement installSource
    throw UnimplementedError();
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) {
    // TODO: implement removeRepo
    throw UnimplementedError();
  }

  @override
  Future<void> uninstallSource(Source source) {
    // TODO: implement uninstallSource
    throw UnimplementedError();
  }

  @override
  Future<void> updateSource(Source source) {
    // TODO: implement updateSource
    throw UnimplementedError();
  }
}

class CloudStreamDesktopPlugin extends DownloadablePlugin {
  @override
  String get name => "cloudStreamDesktop";

  @override
  String get remoteUrl =>
      "https://raw.githubusercontent.com/aayush2622/DartotsuExtensionBridge/master/runtimeManager/builds/cloudStreamDesktop/cloudStreamDesktop-plugin.json";

  @override
  String get fileName => "cloudStreamDesktop-plugin.jar";
}
