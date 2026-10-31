import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../../Engines/JavaEngine/Bridge/JavaBridge.dart';
import '../../../Engines/JavaEngine/Bridge/JavaBridgeFactory.dart';
import '../../../ExtensionBridge.dart';
import '../../../Extensions/DownloadablePlugin.dart';
import '../../Shared/DesktopCorePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Extensions/Extensions.dart';
import '../../../Extensions/SourceMethods.dart';
import '../../../Logger.dart';
import '../../../Models/Source.dart';
import '../../../Network/MClient.dart';
import '../../Shared/JvmBackend.dart';
import '../../Shared/CloudStreamRepoBackend.dart';
import '../CloudStreamSourceMethods.dart';
import 'Models/Source.dart';

class CloudStreamDesktopExtensions extends Extension
    with JvmBackend, DesktopJvmBackend, CloudStreamRepoBackend<CdSource> {
  @override
  String get name => Platform.isIOS ? 'CloudStream' : 'CloudStream (Desktop)';

  @override
  String get id => 'cloudstream_desktop';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/cloudstream.svg";

  @override
  bool get supportsManga => false;

  @override
  bool get supportsNovel => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    CdSource,
    (source) =>
        CloudStreamSourceMethods(source as CdSource, JavaExtensionBridge(java)),
  );

  @override
  DownloadablePlugin plugin = CloudStreamDesktopPlugin();

  @override
  final JavaBridge java = createJavaBridge();

  @override
  String get javaDataDir => 'cloudStream';

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

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    await super.fetchInstalledAnimeExtensions();
    try {
      final dir = await DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/cloudStream/extensions/Anime',
        useSystemPath: false,
        useCustomPath: true,
      );

      // The runtime prepares big plugins in the background (converting one can take minutes), so
      // the list is published as it grows instead of once everything is ready.
      for (var round = 0; round < _maxLoadRounds; round++) {
        final result = await java.call<List<Map<String, dynamic>>>(
          "getInstalledAnimeExtensions",
          {"path": dir!.path},
        );

        anime.installed.value = result
            .map((e) => CdSource.fromJson(e))
            .toList(growable: false);

        if (await _pendingPlugins() <= 0) break;
        await Future<void>.delayed(_loadPollInterval);
      }
    } catch (e) {
      Logger.log("Error fetching installed CloudStream Desktop extensions: $e");
    }
  }

  static const _maxLoadRounds = 300;
  static const _loadPollInterval = Duration(seconds: 2);

  Future<int> _pendingPlugins() async {
    try {
      final pending = await java.call<dynamic>("pendingExtensions");
      return pending is num ? pending.toInt() : 0;
    } catch (_) {
      return 0;
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
        await java.call<bool>('releaseCachedJar', {'jarPath': cached.path});
      } catch (e) {
        Logger.log("Failed to release cached plugin jar on sidecar: $e");
      }

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

class CloudStreamDesktopPlugin extends DesktopPlugin {
  @override
  String get name => "cloudStreamDesktop";

  @override
  String get fileName => "cloudStreamDesktop-plugin.jar";
}
