import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../../Engines/JavaEngine/Bridge/JniBridge.dart';
import '../../../Engines/JavaEngine/Bridge/SidecarBridge.dart';
import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Extensions/ExtensionSettings.dart';
import '../../../Logger.dart';
import '../../../NetworkClient.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../../Shared/TachiyomiRepo.dart';
import '../TsundokuSourceMethods.dart';
import 'Models/Source.dart';

class TsundokuDesktopExtensions extends Extension with TachiyomiRepoBackend {
  @override
  String get id => 'tsundoku_desktop';

  @override
  String get name => 'Tsundoku (Desktop)';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/tsundoku.png";

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    TdSource,
    (source) =>
        TsundokuSourceMethods(source as TdSource, JniExtensionBridge(jni)),
  );
  @override
  DownloadablePlugin plugin = TsundokuDesktopPlugin();

  final JavaBridge jni = SidecarBridge();

  final _client = MClient.init();

  @override
  http.Client get repoClient => _client;

  @override
  List<Source> Function((Uint8List body, String repoUrl, ItemType type))
  get parseIndexIsolate => _parseExtensions;

  @override
  bool get refreshExtensionCountOnFetch => true;
  final _context = DartotsuExtensionBridge.context;

  @override
  Future<bool> onInitialize() async {
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    unawaited(plugin.autoUpdate());

    final filePath = await plugin.getPath();

    await BridgeChannels.init();

    await jni.init(pluginJarPath: filePath);

    var file = await _context.getDirectory(subPath: 'bridge/tsundoku');

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
  void dispose() async {
    super.dispose();
    jni.dispose();
  }

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

  Future<List<Source>> _loadInstalled(String method, ItemType type) async {
    try {
      final dir = await DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/tsundoku/extensions/${type.toString()}',
        useSystemPath: false,
        useCustomPath: true,
      );

      final result = await jni.call<List<Map<String, dynamic>>>(method, {
        "path": dir!.path,
      });

      return result
          .map((e) => TdSource.fromJson(e))
          .where((s) => s.itemType == type)
          .toList(growable: false);
    } catch (e, s) {
      Logger.log("Desktop loadInstalled error: $e\n$s");
      return [];
    }
  }

  @override
  Future<void> installSource(Source source) async {
    final s = source as TdSource;
    final type = source.itemType!;

    final downloadUrl = s.apkUrl;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw Exception("APK URL missing");
    }

    final fileName =
        s.apkName ?? s.pkgName ?? path.basename(Uri.parse(downloadUrl).path);
    if (fileName.isEmpty) {
      throw Exception("Can't determine a file name for ${s.name}");
    }

    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/tsundoku/extensions/${s.itemType.toString()}',
      useSystemPath: false,
      useCustomPath: true,
    );

    final file = File(path.join(dir!.path, fileName));

    final oldApkPath = s.apkPath;

    await downloadPackageFile(_client, downloadUrl, file.path);
    s.apkPath = file.path;

    if (oldApkPath != null && oldApkPath != file.path) {
      final oldFile = File(oldApkPath);
      if (await oldFile.exists()) {
        await oldFile.delete();
        Logger.log('Deleted old extension: ${oldFile.path}');
      }
    }

    final avail = state(type).available;

    avail.value = avail.value.where((e) => e.id != s.id).toList();
    await fetchInstalledExtensions(type);
    final raw = state(type).rawAvailable.value;
    detectUpdates(raw, type);
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as TdSource;
    final type = source.itemType!;

    final apkFileName = s.apkPath != null
        ? path.basename(s.apkPath!)
        : (s.apkName ?? '${s.pkgName ?? s.id}.jar');

    final baseDir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/tsundoku/extensions/${type.toString()}',
      useSystemPath: false,
      useCustomPath: true,
    );

    final file = File(path.join(baseDir!.path, apkFileName));

    if (await file.exists()) {
      await file.delete();
      Logger.log('Deleted private extension: ${s.name}');
    } else {
      Logger.log('Private extension file not found: ${s.name}');
    }

    final raw = state(type).rawAvailable.value;
    final installed = state(type).installed.value;
    final installedIds = installed.map((e) => e.id).toSet();
    state(type).available.value = List.unmodifiable(
      raw.where((e) => !installedIds.contains(e.id)),
    );
    await fetchInstalledExtensions(type);

    detectUpdates(raw, type);
  }

  @override
  Future<void> updateSource(Source source) async => await installSource(source);

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
