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
import '../AniyomiSourceMethods.dart';
import 'Models/Source.dart';

class AniyomiDesktopExtensions extends Extension {
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

      return result
          .map((e) => AdSource.fromJson(e))
          .where((s) => s.itemType == type)
          .toList(growable: false);
    } catch (e, s) {
      Logger.log("Desktop loadInstalled error: $e\n$s");
      return [];
    }
  }

  @override
  Future<void> installSource(Source source) async {
    final s = source as AdSource;
    final type = source.itemType!;
    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/aniyomi/extensions/${s.itemType.toString()}',
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
    final s = source as AdSource;
    final type = source.itemType!;

    final apkFileName = path.basename(s.apkPath!);

    final baseDir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/aniyomi/extensions/${type.toString()}',
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

      final indexUrl = normalizedUrl.endsWith("index.min.json")
          ? normalizedUrl
          : "$normalizedUrl/index.min.json";

      http.Response? res;
      String usedUrl = indexUrl;

      try {
        res = await _client
            .get(Uri.parse(indexUrl))
            .timeout(const Duration(seconds: 10));

        if (res.statusCode != 200) {
          throw Exception("Primary failed");
        }
      } catch (e) {
        Logger.log("Primary repo failed: $indexUrl → $e");

        final fallback = fallbackRepoUrl(normalizedUrl);
        if (fallback == null) {
          throw Exception("Invalid repo & no fallback available");
        }

        final fallbackUrl = "$fallback/index.min.json";

        try {
          res = await _client
              .get(Uri.parse(fallbackUrl))
              .timeout(const Duration(seconds: 10));

          if (res.statusCode != 200) {
            throw Exception("Fallback failed");
          }

          usedUrl = fallbackUrl;
        } catch (e2) {
          Logger.log("Fallback failed: $fallbackUrl → $e2");
          throw Exception("Failed to fetch repo (primary + fallback)");
        }
      }

      final parsed = await compute(_parseExtensions, (res.body, usedUrl, type));

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
  Set<String> get schemes => {"aniyomi", "tachiyomi"};

  @override
  void handleSchemes(Uri uri) {}

  @override
  List<ExtensionSetting> settings(context) => [];
  static List<AdSource> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) {
    final (body, repoUrl, targetType) = args;

    try {
      final decoded = jsonDecode(body);
      if (decoded is! List) return const [];

      final baseIconUrl = repoUrl.endsWith('/index.min.json')
          ? repoUrl.substring(0, repoUrl.length - '/index.min.json'.length)
          : repoUrl;

      final sources = <AdSource>[];

      for (final item in decoded) {
        final map = item as Map<String, dynamic>;
        final name = map['name'] as String? ?? '';

        final detectedType = name.startsWith('Aniyomi: ')
            ? ItemType.anime
            : name.startsWith('Tachiyomi: ')
            ? ItemType.manga
            : null;

        if (detectedType != targetType) continue;

        sources.add(
          AdSource(
            id:
                map["sources"] != null &&
                    map["sources"] is List &&
                    (map["sources"] as List).isNotEmpty
                ? (map["sources"] as List).first['id']?.toString() ?? ''
                : '',
            name: detectedType == ItemType.anime
                ? name.substring(9)
                : name.substring(10),
            pkgName: map['pkg'],
            apkName: map['apk'],
            lang: map['lang'],
            version: map['version'],
            isNsfw: map['nsfw'] == 1,
            itemType: detectedType,
            repo: repoUrl,
            iconUrl: "$baseIconUrl/icon/${map['pkg']}.png",
          ),
        );
      }
      return List.unmodifiable(sources);
    } catch (e) {
      debugPrint("Failed to parse extensions from $repoUrl: $e");
      return const [];
    }
  }

  String? fallbackRepoUrl(String repoUrl) {
    try {
      var stripped = repoUrl
          .replaceFirst(RegExp(r'^https?://'), '')
          .replaceAll(RegExp(r'/+$'), '')
          .replaceAll('/index.min.json', '');

      final parts = stripped.split('/');

      if (parts.length < 3) return null;

      final owner = parts[1];
      final repo = parts[2];
      final branch = parts.length > 3 ? parts[3] : 'main';

      return "https://gcore.jsdelivr.net/gh/$owner/$repo@$branch";
    } catch (_) {
      return null;
    }
  }

  @override
  void detectUpdates(List<Source> available, ItemType type) {
    final installed = state(type).installed.value.cast<AdSource>();

    final repoMap = {for (var s in available.cast<AdSource>()) s.id: s};

    bool changed = false;

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id];

      if (repo == null) continue;

      if (compareVersions(repo.version ?? "0", inst.version ?? "0") > 0) {
        installed[i] = inst
          ..hasUpdate = true
          ..apkName = repo.apkName
          ..iconUrl = repo.iconUrl
          ..versionLast = repo.version;

        changed = true;
      }
    }

    if (changed) {
      state(type).installed.value = List.unmodifiable(installed);
    }
  }

  @override
  Future<List<Source>> fetchRepo(Repo repo, ItemType type) async {
    final indexUrl = repo.url.endsWith("index.min.json")
        ? repo.url
        : "${repo.url.replaceAll(RegExp(r'/+$'), '')}/index.min.json";

    try {
      final res = await _client
          .get(Uri.parse(indexUrl))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        var extensions = await compute(_parseExtensions, (
          res.body,
          indexUrl,
          type,
        ));
        await updateRepoExtensionCount(repo, type, extensions.length);

        return extensions;
      }

      throw Exception("Primary fetch failed");
    } catch (e) {
      Logger.log("Primary repo failed: $indexUrl → $e");

      final fallback = fallbackRepoUrl(repo.url);
      if (fallback == null) return const [];

      final fallbackUrl = "$fallback/index.min.json";

      try {
        final res = await _client
            .get(Uri.parse(fallbackUrl))
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          var extensions = await compute(_parseExtensions, (
            res.body,
            fallbackUrl,
            type,
          ));
          await updateRepoExtensionCount(repo, type, extensions.length);

          return extensions;
        }
      } catch (e2) {
        Logger.log("Fallback failed: $fallbackUrl → $e2");
      }

      return const [];
    }
  }
}

class AniyomiDesktopPlugin extends DownloadablePlugin {
  @override
  String get name => "aniyomiDesktop";

  @override
  String get remoteUrl =>
      "https://raw.githubusercontent.com/aayush2622/DartotsuExtensionBridge/master/runtimeManager/builds/aniyomiDesktop/aniyomiDesktop-plugin.json";

  @override
  String get fileName => "aniyomiDesktop-plugin.jar";
}
