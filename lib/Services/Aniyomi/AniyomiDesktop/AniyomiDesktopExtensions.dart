import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../Engines/JavaEngine/Bridge/JniBridge.dart';
import '../../../Engines/JavaEngine/Bridge/JavaBridgeFactory.dart';
import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Extensions/ExtensionSettings.dart';
import '../../../Logger.dart';
import '../../../NetworkClient.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../../Shared/PackagedSource.dart';
import '../../Shared/TachiyomiJniDesktopExtension.dart';
import '../../Shared/TachiyomiRepo.dart';
import '../AniyomiSourceMethods.dart';
import 'Models/Source.dart';

class AniyomiDesktopExtensions extends Extension
    with TachiyomiRepoBackend, TachiyomiJniDesktopExtension {
  @override
  String get id => 'aniyomi_desktop';

  @override
  String get name => 'Aniyomi (Desktop)';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/aniyomi.png";

  @override
  bool get supportsNovel => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    AdSource,
    (source) =>
        AniyomiSourceMethods(source as AdSource, JniExtensionBridge(jni)),
  );
  @override
  DownloadablePlugin plugin = AniyomiDesktopPlugin();

  final JavaBridge jni = createJavaBridge();

  final _client = MClient.init();
  final _context = DartotsuExtensionBridge.context;

  @override
  http.Client get repoClient => _client;

  @override
  String get jniDataDir => 'aniyomi';

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
  void dispose() async {
    super.dispose();
    jni.dispose();
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

  Future<List<Source>> _loadInstalled(String method, ItemType type) async {
    try {
      final dir = await DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/aniyomi/extensions/${type.toString()}',
        useSystemPath: false,
        useCustomPath: true,
      );

      final result = await jni.call<List<Map<String, dynamic>>>(method, {
        "path": dir!.path,
      });

      final sources = result
          .map((e) => AdSource.fromJson(e))
          .where((s) => s.itemType == type);

      final deduped = _dedupeById(sources);
      await _pruneObsoletePackageFiles(dir, deduped);
      return deduped;
    } catch (e, s) {
      Logger.log("Desktop loadInstalled error: $e\n$s");
      return [];
    }
  }

  /// The native loader keeps only the highest-versioned file per package
  /// when scanning (`byPackage` in AnimeExtensionLoader.desktop.kt /
  /// MangaExtensionLoader.desktop.kt), so a superseded version that
  /// installSource failed to delete never shows up in the list - but it
  /// also never gets deleted, so old .apk files pile up in the extensions
  /// directory indefinitely across app restarts. Sweep anything that isn't
  /// the file currently backing an installed source.
  Future<void> _pruneObsoletePackageFiles(
    Directory dir,
    List<Source> installed,
  ) async {
    final keep = installed
        .whereType<PackagedSource>()
        .map((s) => s.apkPath)
        .whereType<String>()
        .map(p.basename)
        .toSet();

    if (!await dir.exists()) return;

    await for (final entry in dir.list()) {
      if (entry is! File || p.extension(entry.path) != '.apk') continue;
      if (keep.contains(p.basename(entry.path))) continue;

      try {
        await entry.delete();
        Logger.log('Deleted obsolete extension file: ${entry.path}');
      } catch (e) {
        Logger.log(
          'Failed to delete obsolete extension file ${entry.path}: $e',
        );
      }
    }
  }

  /// Guards against duplicate-`GlobalKey` crashes in the extension list UI
  /// (each entry is keyed by [Source.id]). A native-side scan glitch -
  /// e.g. a leftover jar from an update that failed to clean up its old
  /// file, or an entry whose id couldn't be parsed - can otherwise surface
  /// two [Source]s sharing an id. Drops entries with a blank/missing id and
  /// keeps the highest-versioned entry per remaining id.
  List<Source> _dedupeById(Iterable<AdSource> sources) {
    final byId = <String, AdSource>{};

    for (final source in sources) {
      final id = source.id;
      if (id == null || id.isEmpty || id == 'null') {
        Logger.log('Dropping installed source with invalid id: ${source.name}');
        continue;
      }

      final existing = byId[id];
      if (existing == null ||
          _compareVersions(source.version, existing.version) > 0) {
        if (existing != null) {
          Logger.log(
            'Dropping duplicate installed source id=$id '
            '(kept version ${source.version}, dropped ${existing.version})',
          );
        }
        byId[id] = source;
      }
    }

    return byId.values.toList(growable: false);
  }

  int _compareVersions(String? a, String? b) {
    final partsA = (a ?? '').split('.').map(int.tryParse).toList();
    final partsB = (b ?? '').split('.').map(int.tryParse).toList();

    for (var i = 0; i < partsA.length || i < partsB.length; i++) {
      final va = i < partsA.length ? partsA[i] ?? 0 : 0;
      final vb = i < partsB.length ? partsB[i] ?? 0 : 0;
      if (va != vb) return va.compareTo(vb);
    }

    return 0;
  }

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
