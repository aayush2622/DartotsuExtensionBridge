import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Logger.dart';
import '../../../NetworkClient.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../CloudStreamSourceMethods.dart';
import 'Models/CloudStreamSource.dart';

class CloudStreamExtensions extends Extension {
  @override
  String get id => 'cloudstream';

  @override
  String get name => 'CloudStream';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/cloudstream.png";

  @override
  bool get supportsNovel => false;

  @override
  bool get supportsManga => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    CSource,
    (source) => CloudStreamSourceMethods(
      source as CSource,
      MethodChannelBridge(platform),
    ),
  );

  @override
  DownloadablePlugin plugin = CloudStreamPlugin();

  static const platform = MethodChannel('cloudStreamExtensionBridge');
  final _client = MClient.init();

  final _context = DartotsuExtensionBridge.context;
  @override
  Future<bool> onInitialize() async {
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    unawaited(plugin.autoUpdate());

    final filePath = await plugin.getPath();

    await platform.invokeMethod('loadPlugin', {"path": filePath});
    await BridgeChannels.init();
    if (_context.network != null) {
      await platform.invokeMethod(
        'initClient',
        jsonEncode({
          'dns': _context.network?.dns,
          'proxy': _context.network?.proxy,
        }),
      );
    }
    return true;
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    await super.fetchInstalledAnimeExtensions();
    try {
      final dir = await _context.getDirectory(
        subPath: 'bridge/cloudStream/extensions/Anime',
        useSystemPath: false,
        useCustomPath: true,
      );
      final jsonString = await platform.invokeMethod<String>(
        "getInstalledAnimeExtensions",
        dir?.path,
      );

      if (jsonString == null || jsonString.isEmpty) {
        return;
      }

      final List<dynamic> result = jsonDecode(jsonString);
      anime.installed.value = result
          .map((e) => CSource.fromJson(e))
          .toList(growable: false);
    } catch (e) {
      Logger.log("Error fetching installed CloudStream Desktop extensions: $e");
    }
  }

  @override
  Future<void> fetchAnimeExtensions() async {
    await super.fetchAnimeExtensions();
    anime.available.value = await fetchExtensions(ItemType.anime);
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
    final repo = Repo(
      name: repoNameFromUrl(repoUrl),
      url: repoUrl,
      extensions: parsed.length.toString(),
    );

    final updatedRepos = [...repos, repo];
    saveRepos(updatedRepos, type);
    state(type).repos.value = updatedRepos;
    await selectRepo(repo, type);
  }

  @override
  Future<void> installSource(Source source) async {
    final s = source as CSource;
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

    final avail = state(type).available;

    avail.value = avail.value.where((e) => e.id != s.id).toList();

    switch (s.itemType) {
      case ItemType.anime:
        await fetchInstalledAnimeExtensions();
        break;

      default:
        throw Exception('Unsupported item type: ${source.itemType}');
    }
    final raw = state(type).rawAvailable.value;
    detectUpdates(raw, type);
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as CSource;
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

    final raw = state(type).rawAvailable.value;
    final installedIds = state(type).installed.value.map((e) => e.id).toSet();

    state(type).available.value = List.unmodifiable(
      raw.where((e) => !installedIds.contains(e.id)),
    );

    detectUpdates(raw, type);
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

  @override
  Future<List<Source>> fetchRepo(Repo repo, ItemType type) async {
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

  @override
  void detectUpdates(List<Source> available, ItemType type) {
    final installed = state(type).installed.value.cast<CSource>();

    final repoMap = {for (var s in available.cast<CSource>()) s.id: s};

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id];

      if (repo == null) continue;

      if (compareVersions(repo.version ?? "0", inst.version ?? "0") > 0) {
        installed[i] = inst
          ..hasUpdate = true
          ..pluginUrl = repo.pluginUrl
          ..versionLast = repo.version;
      }
      if (repo.iconUrl != inst.iconUrl) {
        installed[i] = inst..iconUrl = repo.iconUrl;
      }
    }
    state(type).installed.value = List.unmodifiable(installed);
  }

  static List<Source> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) {
    final (body, repoUrl, _) = args;

    final decoded = jsonDecode(body) as List;

    return decoded
        .map<Source>((e) {
          final json = e as Map<String, dynamic>;

          return CSource(
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
}

class CloudStreamPlugin extends DownloadablePlugin {
  @override
  String get name => "cloudStreamAndroid";

  @override
  String get fileName => "cloudStreamAndroid-plugin.apk";
}
