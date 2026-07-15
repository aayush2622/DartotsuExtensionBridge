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
import '../IReaderSourceMethods.dart';
import 'Models/Source.dart';

class IreaderDesktopExtensions extends Extension {
  @override
  String get id => 'ireader_desktop';

  @override
  String get name => 'Ireader (Desktop)';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/ireader.png";

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    IdSource,
    (source) =>
        IReaderSourceMethods(source as IdSource, JniExtensionBridge(jni)),
  );
  @override
  DownloadablePlugin plugin = IreaderDesktopPlugin();

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

    var file = await _context.getDirectory(subPath: 'bridge/ireader');

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
        subPath: 'bridge/ireader/extensions/${type.toString()}',
        useSystemPath: false,
        useCustomPath: true,
      );

      final result = await jni.call<List<Map<String, dynamic>>>(method, {
        "path": dir!.path,
      });

      return result
          .map((e) => IdSource.fromJson(e))
          .where((s) => s.itemType == type)
          .toList(growable: false);
    } catch (e, s) {
      Logger.log("Desktop loadInstalled error: $e\n$s");
      return [];
    }
  }

  @override
  Future<void> installSource(Source source) async {
    final s = source as IdSource;
    final type = source.itemType!;
    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/ireader/extensions/${s.itemType.toString()}',
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
    final s = source as IdSource;
    final type = source.itemType!;

    final apkFileName = path.basename(s.apkPath!);

    final baseDir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/ireader/extensions/${type.toString()}',
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

      final repos = loadRepos(type);
      if (repos.any((r) => r.url == repoUrl)) {
        return;
      }

      http.Response? res;

      try {
        res = await _client
            .get(Uri.parse(repoUrl))
            .timeout(const Duration(seconds: 10));

        if (res.statusCode != 200) {
          throw Exception("Primary failed");
        }
      } catch (e) {
        Logger.log("Primary repo failed: $repoUrl → $e");
        throw Exception("Invalid repo & no fallback available");
      }

      final parsed = await compute(_parseExtensions, (res.body, repoUrl, type));

      final repo = Repo(
        name: repoNameFromUrl(repoUrl),
        url: repoUrl,
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
  Set<String> get schemes => {"ireader"};

  @override
  void handleSchemes(Uri uri) {}

  @override
  List<ExtensionSetting> settings(context) => [];
  static List<Source> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) {
    final (body, repoUrl, itemType) = args;

    final decoded = jsonDecode(body) as List;

    final baseRepo = repoUrl.replaceFirst(
      RegExp(r'index(?:\.min)?\.json$'),
      '',
    );

    return decoded
        .map<Source>((e) {
          final json = e as Map<String, dynamic>;

          final apkName = json["apk"] as String?;
          final iconName = apkName?.replaceFirst(RegExp(r'\.apk$'), '');

          return IdSource(
            id: json["id"].toString().toLowerCase(),
            name: json["name"],
            lang: json["lang"],
            isNsfw: json["nsfw"] ?? false,
            version: json["version"]?.toString(),
            versionLast: json["version"]?.toString(),
            itemType: itemType,
            repo: repoUrl,

            apkName: apkName,
            apkUrl: apkName == null ? null : '${baseRepo}apk/$apkName',
            pkgName: json["pkg"],

            iconUrl: iconName == null ? null : '${baseRepo}icon/$iconName.png',
          );
        })
        .toList(growable: false);
  }

  @override
  void detectUpdates(List<Source> available, ItemType type) {
    final installed = state(type).installed.value.cast<IdSource>();

    final repoMap = {for (var s in available.cast<IdSource>()) s.id: s};

    bool changed = false;

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id];

      if (repo == null) continue;

      if (compareVersions(repo.version ?? "0", inst.version ?? "0") > 0) {
        installed[i] = inst
          ..hasUpdate = true
          ..versionLast = repo.version
          ..apkName = repo.apkName
          ..apkUrl = repo.apkUrl
          ..pkgName = repo.pkgName
          ..iconUrl = repo.iconUrl
          ..repo = repo.repo;

        changed = true;
      }
    }

    if (changed) {
      state(type).installed.value = List.unmodifiable(installed);
    }
  }

  @override
  Future<List<Source>> fetchRepo(Repo repo, ItemType type) async {
    try {
      final res = await _client
          .get(Uri.parse(repo.url))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        var extensions = await compute(_parseExtensions, (
          res.body,
          repo.url,
          type,
        ));
        await updateRepoExtensionCount(repo, type, extensions.length);

        return extensions;
      }

      throw Exception("Primary fetch failed");
    } catch (e) {
      Logger.log("repo failed: $repo.url → $e");
    }

    return const [];
  }
}

class IreaderDesktopPlugin extends DownloadablePlugin {
  @override
  String get name => "ireaderDesktop";

  @override
  String get fileName => "ireaderDesktop-plugin.jar";
}
