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

class TsundokuDesktopExtensions extends Extension {
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
    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/tsundoku/extensions/${s.itemType.toString()}',
      useSystemPath: false,
      useCustomPath: true,
    );

    final file = File(path.join(dir!.path, s.apkName));

    if (s.apkUrl == null) {
      throw Exception("APK URL missing");
    }

    final request = http.Request('GET', Uri.parse(s.apkUrl!));
    final response = await _client.send(request);

    final bytes = await response.stream.fold<List<int>>(
      [],
      (a, b) => a..addAll(b),
    );
    await file.writeAsBytes(bytes);
    final oldApkPath = s.apkPath;
    if (oldApkPath != null) {
      final oldFile = File(oldApkPath);
      if (await oldFile.exists() && oldFile.path != file.path) {
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

    final apkFileName = path.basename(s.apkPath!);

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
  Future<void> addRepo(String repoUrl, ItemType type) async {
    try {
      final uri = Uri.tryParse(repoUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception("Invalid repo URL");
      }

      final normalizedUrl = repoUrl.replaceAll(RegExp(r'/+$'), '');

      final repos = loadRepos(type);
      if (repos.any((r) => r.url == normalizedUrl)) {
        return;
      }

      final index = await fetchTachiyomiRepoIndex(_client, normalizedUrl);

      final parsed = await compute(_parseExtensions, (
        index.body,
        index.url,
        type,
      ));

      final repo = Repo(
        name: repoNameFromUrl(repoUrl),
        url: normalizedUrl,
        extensions: parsed.length.toString(),
      );
      final updatedRepos = List<Repo>.from(repos)..add(repo);
      saveRepos(updatedRepos, type);
      state(type).repos.value = updatedRepos;
      await selectRepo(repo, type);
    } catch (e) {
      Logger.log("Failed to add repo $repoUrl: $e");
      rethrow;
    }
  }

  @override
  Set<String> get schemes => {"tsundoku"};

  @override
  void handleSchemes(Uri uri) {}

  @override
  List<ExtensionSetting> settings(context) => [];
  static List<TdSource> _parseExtensions(
    (Uint8List body, String repoUrl, ItemType itemType) args,
  ) {
    final (body, repoUrl, targetType) = args;

    if (tachiyomiIndexFormat(repoUrl) == RepoIndexFormat.protobuf) {
      return parseTachiyomiPbIndex<TdSource>(
        body: body,
        repoUrl: repoUrl,
        targetType: targetType,
        factory: _sourceFromEntry,
      );
    }

    return parseTachiyomiRepoIndex<TdSource>(
      body: utf8.decode(body, allowMalformed: true),
      repoUrl: repoUrl,
      targetType: targetType,
      prefixes: const {'Tsundoku: ': ItemType.novel},
      factory: _sourceFromEntry,
    );
  }

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

  @override
  void detectUpdates(List<Source> available, ItemType type) =>
      detectTachiyomiUpdates(this, available, type);

  @override
  Future<List<Source>> fetchRepo(Repo repo, ItemType type) async {
    try {
      final index = await fetchTachiyomiRepoIndex(_client, repo.url);
      final extensions = await compute(_parseExtensions, (
        index.body,
        index.url,
        type,
      ));
      await updateRepoExtensionCount(repo, type, extensions.length);
      return extensions;
    } catch (e) {
      Logger.log("Failed to fetch repo ${repo.url}: $e");
      return const [];
    }
  }
}

class TsundokuDesktopPlugin extends DownloadablePlugin {
  @override
  String get name => "tsundokuDesktop";

  @override
  String get fileName => "tsundokuDesktop-plugin.jar";
}
