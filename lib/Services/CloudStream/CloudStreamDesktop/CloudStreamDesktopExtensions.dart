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
import '../../Shared/CloudStreamSource.dart';
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
      final first = _watching == 0;
      if (first) unawaited(_watch(++_generation));
      await java.call<dynamic>('scanExtensions', {'path': dir!.path}, true);
      if (first) await _settle();
    } catch (e) {
      Logger.log("Error fetching installed CloudStream Desktop extensions: $e");
    }
  }

  @override
  Future<void> unloadRemovedPlugins() async {
    final dir = await extensionsDir;
    if (dir == null) return;
    try {
      await java.call<dynamic>('scanExtensions', {'path': dir.path}, true);
    } catch (e) {
      Logger.log('Could not unload removed CloudStream plugins: $e');
    }
  }

  @override
  Future<void> releaseRuntimeFile() {
    _generation++;
    _watching = 0;
    return super.releaseRuntimeFile();
  }

  @override
  void dispose() {
    _generation++;
    _watching = 0;
    super.dispose();
  }

  int _generation = 0;
  int _watching = 0;

  static const _pollWait = 25000;
  static const _settleLimit = Duration(seconds: 12);

  Future<void> _settle() async {
    final deadline = DateTime.now().add(_settleLimit);
    while (DateTime.now().isBefore(deadline)) {
      if (await _pendingPlugins() <= 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<int> _pendingPlugins() async {
    try {
      final pending = await java.call<dynamic>('pendingExtensions');
      return pending is num ? pending.toInt() : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Long-polls the runtime for plugins that changed and applies each change to
  /// the installed list on its own, so one plugin coming or going never reloads
  /// the others.
  Future<void> _watch(int generation) async {
    _watching = generation;
    var since = 0;
    while (_generation == generation) {
      try {
        final reply = await java.call<dynamic>('extensionChanges', {
          'since': since,
          'waitMs': _pollWait,
        }, true);
        if (_generation != generation) break;
        if (reply is! Map) continue;
        since = (reply['version'] as num?)?.toInt() ?? since;
        final entries = reply['entries'];
        if (entries is List && entries.isNotEmpty) {
          _apply(entries.map((e) => Map<String, dynamic>.from(e as Map)));
        }
      } catch (e) {
        if (_generation != generation) break;
        Logger.log('CloudStream plugin watcher: $e');
        since = 0;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    if (_watching == generation) _watching = 0;
  }

  static String? _pluginOf(Source s) =>
      s is CloudStreamSource ? s.sourcePlugin : null;

  void _apply(Iterable<Map<String, dynamic>> entries) {
    final replacement = <String, List<Source>>{};
    var readied = false;
    for (final entry in entries) {
      final pluginPath = entry['path'] as String;
      final state = entry['state'] as String? ?? 'queued';
      final ghostId = '${Source.placeholderPrefix}$pluginPath';
      final progress = (entry['progress'] as num?)?.toDouble() ?? 0.0;
      switch (state) {
        case 'ready':
          final sources = entry['sources'];
          replacement[pluginPath] = sources is List
              ? sources
                    .map(
                      (e) => CdSource.fromJson(
                        Map<String, dynamic>.from(e as Map),
                      ),
                    )
                    .toList(growable: false)
              : const [];
          anime.installProgress.remove(ghostId);
          readied = true;
        case 'removed':
          replacement[pluginPath] = const [];
          anime.installProgress.remove(ghostId);
        default:
          replacement[pluginPath] = [
            CdSource(
              id: ghostId,
              name: entry['name'] as String? ?? pluginPath,
              lang: 'en',
              iconUrl: '',
              itemType: ItemType.anime,
              version: switch (state) {
                'converting' => 'Converting',
                'loading' => 'Loading',
                'failed' => 'Failed',
                _ => 'Queued',
              },
              versionLast: '',
              sourcePlugin: pluginPath,
            ),
          ];
          if (state == 'failed') {
            anime.installProgress.remove(ghostId);
          } else {
            anime.installProgress[ghostId] = state == 'queued' ? 0.0 : progress;
          }
      }
    }

    final placed = <String>{};
    final next = <Source>[];
    for (final source in anime.installed.value) {
      final owner = _pluginOf(source);
      if (owner == null || !replacement.containsKey(owner)) {
        next.add(source);
      } else if (placed.add(owner)) {
        next.addAll(replacement[owner]!);
      }
    }
    for (final e in replacement.entries) {
      if (!placed.contains(e.key)) next.addAll(e.value);
    }
    anime.installed.value = next;
    if (readied) {
      detectUpdates(anime.rawAvailable.value, ItemType.anime);
      syncAvailable(ItemType.anime);
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
