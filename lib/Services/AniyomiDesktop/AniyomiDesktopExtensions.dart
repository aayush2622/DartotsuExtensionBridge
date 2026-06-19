import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../Engines/JavaEngine/Bridge/JniBridge.dart';
import '../../Engines/JavaEngine/Bridge/SidecarBridge.dart';
import '../../Extensions/DownloadablePlugin.dart';
import '../../Extensions/ExtensionSettings.dart';
import '../../Logger.dart';
import '../../NetworkClient.dart';
import '../../Settings/KvStore.dart';
import '../../dartotsu_extension_bridge.dart';
import '../Network.dart';
import 'AniyomiDesktopSourceMethods.dart';
import 'AniyomiService.dart';
import 'Models/Source.dart';

class AniyomiDesktopExtensions extends Extension {
  @override
  String get id => 'aniyomi_desktop';

  @override
  String get name => 'Aniyomi (Desktop)';

  @override
  bool get supportsNovel => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    AdSource,
    (source) => AniyomiSourceMethodsDesktop(source as AdSource, jni),
  );

  @override
  DownloadablePlugin plugin = AniyomiDesktopPlugin();

  final JavaBridge jni = (() {
    final useSidecar = getVal("aniyomiDesktopUseSidecar") ?? false;

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

    await jni.init(pluginJarPath: filePath, handler: AniyomiService());

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

    final file = File("${dir!.path}/${s.apkName}");

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

    final avail = getAvailableRx(s.itemType!);

    avail.value = avail.value.where((e) => e.id != s.id).toList();

    switch (s.itemType) {
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
    final raw = getRawAvailableRx(type).value;
    _detectUpdates(raw.map((e) => e as AdSource).toList(), type);
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

    final raw = getRawAvailableRx(type).value;
    final installed = getInstalledRx(type).value;
    final installedIds = installed.map((e) => e.id).toSet();
    getAvailableRx(type).value = List.unmodifiable(
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
    _detectUpdates(raw.map((e) => e as AdSource).toList(), type);
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

      final repos = _loadRepos(type);
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
        url: normalizedUrl,
        extensions: parsed.length.toString(),
      );
      final updatedRepos = List<Repo>.from(repos)..add(repo);
      _saveRepos(updatedRepos, type);

      final rx = getAvailableRx(type);
      final existing = rx.value;

      final merged = {
        for (final s in existing) s.id: s,
        for (final s in parsed) s.id: s,
      }.values.toList(growable: false);

      rx.value = List.unmodifiable(merged);

      getReposRx(type).value = updatedRepos;
    } catch (e) {
      Logger.log("Failed to add repo $repoUrl: $e");
      rethrow;
    }
  }

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
            isNsfw: map['isNsfw'] ?? false,
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

  Future<List<Source>> _fetchExtensions(ItemType type) async {
    final repos = _loadRepos(type);
    if (repos.isEmpty) return const [];

    getReposRx(type).value = repos;

    final results = await Future.wait(repos.map((r) => _fetchRepo(r, type)));

    final all = results.expand((e) => e).toList(growable: false);

    final installed = getInstalledRx(type).value;
    final installedIds = installed.map((e) => e.id).toSet();

    _detectUpdates(all.map((e) => e as AdSource).toList(), type);

    getRawAvailableRx(type).value = List.unmodifiable(all);

    return List.unmodifiable(all.where((s) => !installedIds.contains(s.id)));
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

  void _detectUpdates(List<AdSource> available, ItemType type) {
    final installed = getInstalledRx(type).value.cast<AdSource>();

    final repoMap = {for (var s in available) s.id: s};

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
      getInstalledRx(type).value = List.unmodifiable(installed);
    }
  }

  Future<List<Source>> _fetchRepo(Repo repo, ItemType type) async {
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

  @override
  Future<void> fetchAnimeExtensions() async {
    await super.fetchAnimeExtensions();
    final res = await _fetchExtensions(ItemType.anime);
    getAvailableRx(ItemType.anime).value = res;
  }

  @override
  Future<void> fetchMangaExtensions() async {
    await super.fetchMangaExtensions();
    final res = await _fetchExtensions(ItemType.manga);
    getAvailableRx(ItemType.manga).value = res;
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {
    try {
      final repos = _loadRepos(
        type,
      ).where((r) => r.url != repoUrl).toList(growable: false);

      _saveRepos(repos, type);

      final rx = getAvailableRx(type);
      rx.value = rx.value.where((s) => s.repo != repoUrl).toList();

      getReposRx(type).value = repos;
    } catch (e) {
      Logger.log("Failed to remove repo $repoUrl: $e");
    }
  }

  List<Repo> _loadRepos(ItemType type) {
    final encoded = getVal<List<String>>('$id${type.name}Repos');
    if (encoded == null || encoded.isEmpty) return const [];

    final repos = encoded.map((e) => Repo.fromJson(jsonDecode(e)));

    return {for (final r in repos) r.url: r}.values.toList(growable: false);
  }

  void _saveRepos(List<Repo> repos, ItemType type) {
    final key = '$id${type.name}Repos';

    final unique = {for (final r in repos) r.url: r}.values;

    setVal(
      key,
      unique.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }

  @override
  Set<String> get schemes => {"aniyomi", "tachiyomi"};

  @override
  void handleSchemes(Uri uri) {}

  @override
  List<ExtensionSetting> settings(context) => [
    ExtensionSetting(
      type: ExtensionSettingType.switchType,
      name: "Use Sidecar",
      description:
          "Use the Sidecar bridge instead of JNI. Requires a restart and the Sidecar runtime to be installed. May improve stability but can cause issues on some systems.",
      icon: Icons.settings_ethernet_rounded,
      isChecked: getVal("aniyomiDesktopUseSidecar") ?? false,
      isVisible: Platform.isWindows || Platform.isLinux,
      onSwitchChange: (v) async {
        setVal("aniyomiDesktopUseSidecar", v);
        Logger.log(
          "Set useSidecar to $v. Restart the app for changes to take effect.",
          show: true,
        );
      },
    ),
  ];
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
