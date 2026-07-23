import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:install_plugin/install_plugin.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Extensions/ExtensionSettings.dart';
import '../../../Logger.dart';
import '../../../NetworkClient.dart';
import '../../../Settings/KvStore.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../AniyomiSourceMethods.dart';
import 'Models/Source.dart';

class AniyomiExtensions extends Extension {
  final _client = MClient.init();

  @override
  String get id => 'aniyomi';

  @override
  String get name => 'Aniyomi';

  @override
  bool get supportsNovel => false;

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/aniyomi.png";

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    ASource,
    (source) =>
        AniyomiSourceMethods(source as ASource, MethodChannelBridge(platform)),
  );

  @override
  DownloadablePlugin plugin = AniyomiPlugin();
  final platform = const MethodChannel('aniyomiExtensionBridge');

  @override
  Future<bool> onInitialize() async {
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    unawaited(plugin.autoUpdate());

    final filePath = await plugin.getPath();

    await platform.invokeMethod('loadPlugin', {"path": filePath});
    await BridgeChannels.init();
    var context = DartotsuExtensionBridge.context;
    if (context.network != null) {
      await platform.invokeMethod(
        'initClient',
        jsonEncode({
          'dns': context.network?.dns,
          'proxy': context.network?.proxy,
        }),
      );
    }
    return true;
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

  @override
  Future<void> installSource(Source source) async {
    final aSource = source as ASource;
    final isPrivate = getVal('aniyomiInstallPrivate') ?? false;
    final type = source.itemType!;
    if (aSource.apkUrl == null) {
      throw Exception('Source APK URL is required for installation.');
    }

    try {
      final packageName =
          aSource.pkgName ??
          aSource.apkUrl!.split('/').last.replaceAll('.apk', '');

      final apkFileName = '$packageName.apk';

      final request = http.Request('GET', Uri.parse(aSource.apkUrl!));

      final response = await _client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Extension download failed (${response.statusCode})');
      }

      if (isPrivate) {
        final extDir = await DartotsuExtensionBridge.context.getDirectory(
          subPath: 'bridge/aniyomi-extensions/${aSource.itemType}',
          useSystemPath: false,
          useCustomPath: true,
        );

        if (extDir == null) {
          throw Exception('Failed to get extension directory');
        }

        await extDir.create(recursive: true);

        final file = File(path.join(extDir.path, apkFileName));

        final sink = file.openWrite();

        await response.stream.pipe(sink);

        await sink.close();

        Logger.log('Installed PRIVATE extension: ${aSource.pkgName}');
      } else {
        final tempDir = await getTemporaryDirectory();

        final apkFile = File(path.join(tempDir.path, apkFileName));

        final sink = apkFile.openWrite();

        await response.stream.pipe(sink);

        await sink.close();

        final result = await InstallPlugin.installApk(
          apkFile.path,
          appId: packageName,
        );

        if (await apkFile.exists()) {
          await apkFile.delete();
        }

        if (result['isSuccess'] != true) {
          throw Exception(
            'Installation failed: '
            '${result['errorMessage'] ?? 'Unknown error'}',
          );
        }

        Logger.log('Installed SHARED extension: $packageName');
      }

      final avail = state(type).available;

      avail.value = avail.value.where((e) => e.id != aSource.id).toList();

      switch (aSource.itemType) {
        case ItemType.anime:
          await fetchInstalledAnimeExtensions();
          break;

        case ItemType.manga:
          await fetchInstalledMangaExtensions();
          break;

        case ItemType.novel:
          break;

        default:
          throw Exception('Unsupported item type: ${source.itemType}');
      }
      final raw = state(type).rawAvailable.value;
      detectUpdates(raw, type);
    } catch (e) {
      Logger.log('Error installing source: $e');
      rethrow;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as ASource;
    final type = source.itemType!;
    final packageName =
        s.pkgName ?? s.apkUrl!.split('/').last.replaceAll('.apk', '');
    final apkFileName = '$packageName.apk';
    try {
      if (s.isShared == false) {
        final baseDir = await DartotsuExtensionBridge.context.getDirectory(
          subPath: 'bridge/aniyomi-extensions/${type.toString()}',
          useSystemPath: false,
          useCustomPath: true,
        );

        final file = File(path.join(baseDir!.path, apkFileName));

        if (await file.exists()) {
          await file.delete();
          Logger.log('Deleted private extension: ${s.pkgName}');
        } else {
          Logger.log('Private extension file not found: ${s.pkgName}');
        }
        final raw = state(type).rawAvailable.value;
        final installed = state(type).installed.value;
        final installedIds = installed.map((e) => e.id).toSet();

        state(type).available.value = List.unmodifiable(
          raw.where((e) => !installedIds.contains(e.id)),
        );

        switch (type) {
          case ItemType.anime:
            await fetchInstalledAnimeExtensions();
            break;
          case ItemType.manga:
            await fetchInstalledMangaExtensions();
            break;
          case ItemType.novel:
            break;
        }
        detectUpdates(raw, type);
        return;
      }

      final packageName = s.pkgName;
      if (packageName == null || packageName.isEmpty) {
        throw Exception('Package name is required for uninstall.');
      }

      final isInstalled =
          await InstalledApps.isAppInstalled(packageName) ?? false;

      if (!isInstalled) {
        state(type).installed.value = state(
          type,
        ).installed.value.where((e) => e.id != s.id).toList();
        return;
      }

      final success = await InstalledApps.uninstallApp(packageName) ?? false;
      if (!success) {
        throw Exception('Failed to initiate uninstallation for: $packageName');
      }

      final timeout = const Duration(seconds: 10);
      final start = DateTime.now();

      while (DateTime.now().difference(start) < timeout) {
        final stillInstalled =
            await InstalledApps.isAppInstalled(packageName) ?? false;
        if (!stillInstalled) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final finalCheck =
          await InstalledApps.isAppInstalled(packageName) ?? false;
      if (finalCheck) {
        throw Exception('Uninstallation timed out or was cancelled by user.');
      }

      Logger.log('Uninstalled shared extension: $packageName');

      final raw = state(type).rawAvailable.value;
      final installed = state(type).installed.value;
      final installedIds = installed.map((e) => e.id).toSet();

      state(type).available.value = List.unmodifiable(
        raw.where((e) => !installedIds.contains(e.id)),
      );

      switch (type) {
        case ItemType.anime:
          await fetchInstalledAnimeExtensions();
          break;
        case ItemType.manga:
          await fetchInstalledMangaExtensions();
          break;
        case ItemType.novel:
          break;
      }
      detectUpdates(raw, type);
    } catch (e) {
      Logger.log('Error uninstalling source: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    await installSource(source);
  }

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
  void handleSchemes(Uri uri) {
    final url = uri.queryParameters["url"];
    if (url != null && url.isNotEmpty) {
      addRepo(url, uri.scheme == "aniyomi" ? ItemType.anime : ItemType.manga);
    }
  }

  @override
  List<ExtensionSetting> settings(BuildContext context) {
    return [
      ExtensionSetting(
        name: "Install Extensions Privately",
        description:
            "Install extensions in a private directory (extensions won't be visible to other apps)",
        type: ExtensionSettingType.switchType,
        isChecked: getVal('aniyomiInstallPrivate') ?? false,
        onSwitchChange: (value) => setVal('aniyomiInstallPrivate', value),
        icon: Icons.lock_outline,
      ),
    ];
  }

  Future<List<Source>> _loadInstalled(String method, ItemType type) async {
    try {
      var path = await DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/aniyomi-extensions/${type.toString()}',
        useSystemPath: false,
        useCustomPath: true,
      );
      final jsonString = await platform.invokeMethod<String>(
        method,
        path?.path,
      );

      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> result = jsonDecode(jsonString);

      return result
          .map((e) => ASource.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.itemType == type)
          .toList(growable: false);
    } catch (e) {
      return [];
    }
  }

  static List<ASource> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) {
    final (body, repoUrl, targetType) = args;

    try {
      final decoded = jsonDecode(body);
      if (decoded is! List) return const [];

      final baseIconUrl = repoUrl.endsWith('/index.min.json')
          ? repoUrl.substring(0, repoUrl.length - '/index.min.json'.length)
          : repoUrl;

      final sources = <ASource>[];

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
          ASource(
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
      Logger.log("Failed to parse extensions from $repoUrl: $e");
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
    final installed = state(type).installed.value.cast<ASource>();

    final repoMap = {for (var s in available.cast<ASource>()) s.id: s};

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
        return compute(_parseExtensions, (res.body, indexUrl, type));
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
          return compute(_parseExtensions, (res.body, fallbackUrl, type));
        }
      } catch (e2) {
        Logger.log("Fallback failed: $fallbackUrl → $e2");
      }

      return const [];
    }
  }
}

class AniyomiPlugin extends DownloadablePlugin {
  @override
  String get name => "aniyomiAndroid";

  @override
  String get fileName => "aniyomiAndroid-plugin.apk";
}
