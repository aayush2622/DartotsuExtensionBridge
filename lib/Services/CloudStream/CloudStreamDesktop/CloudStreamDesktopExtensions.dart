import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../../Engines/JavaEngine/Bridge/JniBridge.dart';
import '../../../Engines/JavaEngine/Bridge/JavaBridgeFactory.dart';
import '../../../ExtensionBridge.dart';
import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Extensions/Extensions.dart';
import '../../../Extensions/SourceMethods.dart';
import '../../../Logger.dart';
import '../../../Models/Source.dart';
import '../../../NetworkClient.dart';
import '../../Network.dart';
import '../../Shared/CloudStreamRepoBackend.dart';
import '../CloudStreamSourceMethods.dart';
import 'Models/Source.dart';

class CloudStreamDesktopExtensions extends Extension
    with CloudStreamRepoBackend<CdSource> {
  @override
  String get name => 'CloudStream (Desktop)';

  @override
  String get id => 'cloudstream_desktop';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/cloudstream.png";

  @override
  bool get supportsManga => false;

  @override
  bool get supportsNovel => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    CdSource,
    (source) =>
        CloudStreamSourceMethods(source as CdSource, JniExtensionBridge(jni)),
  );

  @override
  DownloadablePlugin plugin = CloudStreamDesktopPlugin();

  final JavaBridge jni = createJavaBridge();

  final _client = MClient.init();

  @override
  http.Client get repoClient => _client;

  @override
  Future<Directory?> get extensionsDir =>
      DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/cloudStream/extensions/Anime',
        useSystemPath: false,
        useCustomPath: true,
      );

  @override
  List<Source> Function((String body, String repoUrl, ItemType type))
  get parseExtensionsIsolate => _parseExtensions;

  final _context = DartotsuExtensionBridge.context;

  @override
  Future<bool> onInitialize() async {
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    unawaited(plugin.autoUpdate());

    final filePath = await plugin.getPath();

    await BridgeChannels.init();

    await jni.init(pluginJarPath: filePath);

    var file = await _context.getDirectory(subPath: 'bridge/aniyomi');

    await jni.call<void>("initializeDesktop", {"path": file!.path});

    if (_context.network != null) {
      await jni.call<void>("initClient", {
        "data": jsonEncode({
          "dns": _context.network?.dns,
          "proxy": _context.network?.proxy,
          "userAgent": _context.network?.userAgent,
        }),
      });
    }

    return true;
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    await super.fetchInstalledAnimeExtensions();
    try {
      final dir = await DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/cloudStream/extensions/Anime',
        useSystemPath: false,
        useCustomPath: true,
      );
      final result = await jni.call<List<Map<String, dynamic>>>(
        "getInstalledAnimeExtensions",
        {"path": dir!.path},
      );

      anime.installed.value = result
          .map((e) => CdSource.fromJson(e))
          .toList(growable: false);
    } catch (e) {
      Logger.log("Error fetching installed CloudStream Desktop extensions: $e");
    }
  }

  @override
  Future<void> fetchAnimeExtensions() async {
    await super.fetchAnimeExtensions();
    anime.available.value = await fetchExtensions(ItemType.anime);
  }

  Future<void> _deleteCachedJar(File sourceFile) async {
    final cached = File(
      path.join(
        sourceFile.parent.path,
        'jar',
        "${path.basenameWithoutExtension(sourceFile.path)}.jar",
      ),
    );
    if (await cached.exists()) {
      try {
        await cached.delete();
      } catch (e) {
        Logger.log("Failed to delete cached plugin jar: $e");
      }
    }
  }

  @override
  Future<void> onSourceFileWritten(File file) => _deleteCachedJar(file);

  @override
  Future<void> onSourceFileDeleted(File file) => _deleteCachedJar(file);

  @override
  void dispose() async {
    super.dispose();
    jni.dispose();
  }

  static List<CdSource> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) => parseCloudStreamRepoBody<CdSource>(args.$1, args.$2, _sourceFromEntry);

  static CdSource _sourceFromEntry(CloudStreamRepoEntry e) => CdSource(
    id: e.id,
    name: e.name,
    baseUrl: e.baseUrl,
    lang: e.lang,
    iconUrl: e.iconUrl,
    isNsfw: e.isNsfw,
    version: e.version,
    versionLast: e.version,
    itemType: ItemType.anime,
    repo: e.repo,
    internalName: e.internalName,
    pluginUrl: e.pluginUrl,
  );
}

class CloudStreamDesktopPlugin extends DownloadablePlugin {
  @override
  String get name => "cloudStreamDesktop";

  @override
  String get fileName => "cloudStreamDesktop-plugin.jar";
}
