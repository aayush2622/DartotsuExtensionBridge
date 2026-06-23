import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../Engines/JavaEngine/Bridge/JniBridge.dart';
import '../../Engines/JavaEngine/Bridge/SidecarBridge.dart';
import '../../ExtensionBridge.dart';
import '../../Extensions/DownloadablePlugin.dart';
import '../../Extensions/ExtensionSettings.dart';
import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../NetworkClient.dart';
import '../../Settings/KvStore.dart';
import '../Network.dart';
import 'CloudStreamService.dart';
import 'ClousStreamDesktopSourceMethods.dart';
import 'Models/Source.dart';

class CloudStreamDesktopExtensions extends Extension {
  @override
  String get name => 'CloudStream (Desktop)';

  @override
  String get id => 'cloudstream_desktop';

  @override
  bool get supportsManga => false;

  @override
  bool get supportsNovel => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    CdSource,
    (source) => CloudStreamSourceMethodsDesktop(source as CdSource, jni),
  );

  @override
  DownloadablePlugin plugin = CloudStreamDesktopPlugin();

  final JavaBridge jni = (() {
    final useSidecar = getVal("cloudStreamDesktopUseSidecar") ?? false;

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

    await jni.init(pluginJarPath: filePath, handler: CloudStreamService());

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

      getInstalledRx(ItemType.anime).value = result
          .map((e) => CdSource.fromJson(e))
          .toList(growable: false);
    } catch (e) {
      Logger.log("Error fetching installed CloudStream Desktop extensions: $e");
    }
  }

  @override
  Future<void> fetchAnimeExtensions() async {
    await super.fetchAnimeExtensions();
    final res = await _fetchExtensions(ItemType.anime);
    getAvailableRx(ItemType.anime).value = res;
  }

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    final uri = Uri.tryParse(repoUrl);
    if (uri == null || !uri.hasScheme) {
      throw Exception("Invalid repo URL");
    }

    final repos = loadRepos(type);

    if (repos.any((r) => r.url == repoUrl)) {
      return;
    }

    final res = await _client
        .get(Uri.parse(repoUrl))
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw Exception("Repo returned ${res.statusCode}");
    }

    final decoded = jsonDecode(res.body);

    if (decoded is Map<String, dynamic>) {
      final pluginLists = decoded["pluginLists"];

      if (pluginLists is List) {
        for (final subRepo in pluginLists.cast<String>()) {
          try {
            await addRepo(subRepo, type);
          } catch (e) {
            Logger.log("Failed to add $subRepo: $e");
          }
        }
        return;
      }

      throw Exception("Invalid CloudStream repository");
    }

    if (decoded is! List) {
      throw Exception("Invalid CloudStream repository");
    }

    final parsed = await compute(_parseExtensions, (res.body, repoUrl, type));
    final repo = Repo(url: repoUrl, extensions: parsed.length.toString());

    final updatedRepos = [...repos, repo];
    saveRepos(updatedRepos, type);

    getReposRx(type).value = updatedRepos;

    final existing = getAvailableRx(type).value;

    getAvailableRx(type).value = List.unmodifiable(
      {
        for (final s in existing) s.id: s,
        for (final s in parsed) s.id: s,
      }.values,
    );
  }

  @override
  Future<void> installSource(Source source) async {
    final s = source as CdSource;
    final type = source.itemType!;
    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/cloudStream/extensions/Anime',
      useSystemPath: false,
      useCustomPath: true,
    );

    final file = File(
      path.join(dir!.path, path.basename(Uri.parse(s.pluginUrl!).path)),
    );

    if (s.pluginUrl == null) {
      throw Exception("APK URL missing");
    }

    final request = http.Request('GET', Uri.parse(s.pluginUrl!));
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

      default:
        throw Exception('Unsupported item type: ${source.itemType}');
    }
    final raw = getRawAvailableRx(type).value;
    _detectUpdates(raw.map((e) => e as CdSource).toList(), type);
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as CdSource;
    final type = source.itemType!;

    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/cloudStream/extensions/Anime',
      useSystemPath: false,
      useCustomPath: true,
    );

    File? pluginFile;

    await for (final entity in dir!.list()) {
      if (entity is! File) continue;

      if (path.basenameWithoutExtension(entity.path) == s.internalName) {
        pluginFile = entity;
        break;
      }
    }

    if (pluginFile != null) {
      await pluginFile.delete();
      Logger.log("Deleted private extension: ${s.name}");
    } else {
      Logger.log("Private extension file not found: ${s.name}");
    }

    switch (type) {
      case ItemType.anime:
        await fetchInstalledAnimeExtensions();
        break;
      default:
        throw Exception("Unsupported item type: $type");
    }

    final raw = getRawAvailableRx(type).value;
    final installedIds = getInstalledRx(type).value.map((e) => e.id).toSet();

    getAvailableRx(type).value = List.unmodifiable(
      raw.where((e) => !installedIds.contains(e.id)),
    );

    _detectUpdates(raw.cast<CdSource>(), type);
  }

  @override
  Future<void> updateSource(Source source) async => await installSource(source);

  @override
  Set<String> schemes = {"cloudstreamrepo"};

  @override
  Future<void> handleSchemes(Uri uri) async {
    final urlWithoutScheme = uri.toString().replaceFirst(
      'cloudstreamrepo://',
      '',
    );

    await addRepo(
      urlWithoutScheme.startsWith('http')
          ? urlWithoutScheme
          : 'https://$urlWithoutScheme',
      ItemType.anime,
    );
  }

  Future<List<Source>> _fetchExtensions(ItemType type) async {
    final repos = loadRepos(type);
    if (repos.isEmpty) return const [];

    getReposRx(type).value = repos;

    final results = await Future.wait(repos.map((r) => _fetchRepo(r, type)));

    final all = results.expand((e) => e).toList(growable: false);

    final installed = getInstalledRx(type).value;
    final installedIds = installed.map((e) => e.id).toSet();

    _detectUpdates(all.map((e) => e as CdSource).toList(), type);

    getRawAvailableRx(type).value = List.unmodifiable(all);

    return List.unmodifiable(all.where((s) => !installedIds.contains(s.id)));
  }

  Future<List<Source>> _fetchRepo(Repo repo, ItemType type) async {
    final indexUrl = repo.url;
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
    return [];
  }

  void _detectUpdates(List<CdSource> available, ItemType type) {
    final installed = getInstalledRx(type).value.cast<CdSource>();

    final repoMap = {for (var s in available) s.id: s};

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id];

      if (repo == null) continue;

      if (compareVersions(repo.version ?? "0", inst.version ?? "0") > 0) {
        installed[i] = inst
          ..hasUpdate = true
          ..versionLast = repo.version;
      }
      if (repo.iconUrl != inst.iconUrl) {
        installed[i] = inst..iconUrl = repo.iconUrl;
      }
    }
    getInstalledRx(type).value = List.unmodifiable(installed);
  }

  static List<Source> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) {
    final (body, repoUrl, _) = args;

    final decoded = jsonDecode(body) as List;

    return decoded
        .map<Source>((e) {
          final json = e as Map<String, dynamic>;

          return CdSource(
            id: (json["internalName"] ?? json["name"]).toString().toLowerCase(),
            name: json["name"],
            baseUrl: json["url"],
            lang: json["language"],
            iconUrl: json["iconUrl"],
            isNsfw: json["isNsfw"] ?? false,
            version: json["version"]?.toString(),
            versionLast: json["version"]?.toString(),
            itemType: ItemType.anime,
            repo: repoUrl,
            internalName: json["internalName"] ?? json["name"],
            pluginUrl: json["url"],
          );
        })
        .toList(growable: false);
  }

  @override
  List<ExtensionSetting> settings(context) => [
    ExtensionSetting(
      type: ExtensionSettingType.switchType,
      name: "Use Sidecar",
      description:
          "Use the Sidecar bridge instead of JNI. Requires a restart and the Sidecar runtime to be installed. May improve stability but can cause issues on some systems.",
      icon: Icons.settings_ethernet_rounded,
      isChecked: getVal("cloudStreamDesktopUseSidecar") ?? false,
      isVisible: Platform.isWindows || Platform.isLinux,
      onSwitchChange: (v) async {
        setVal("cloudStreamDesktopUseSidecar", v);
        Logger.log(
          "Set useSidecar to $v. Restart the app for changes to take effect.",
          show: true,
        );
      },
    ),
  ];
}

class CloudStreamDesktopPlugin extends DownloadablePlugin {
  @override
  String get name => "cloudStreamDesktop";

  @override
  String get remoteUrl =>
      "https://raw.githubusercontent.com/aayush2622/DartotsuExtensionBridge/master/runtimeManager/builds/cloudStreamDesktop/cloudStreamDesktop-plugin.json";

  @override
  String get fileName => "cloudStreamDesktop-plugin.jar";
}
