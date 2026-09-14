import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../Engines/JavaEngine/Bridge/JniBridge.dart';
import '../../../Engines/JavaEngine/Bridge/JavaBridgeFactory.dart';
import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Extensions/ExtensionSettings.dart';
import '../../../Logger.dart';
import '../../../NetworkClient.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../../Shared/TachiyomiJniDesktopExtension.dart';
import '../IReaderSourceMethods.dart';
import 'Models/Source.dart';

class IReaderDesktopExtensions extends Extension
    with TachiyomiJniDesktopExtension {
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

  final JavaBridge jni = createJavaBridge();

  final _client = MClient.init();
  final _context = DartotsuExtensionBridge.context;

  @override
  http.Client get repoClient => _client;

  @override
  String get jniDataDir => 'ireader';

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
  Stream<double> addRepo(String repoUrl, ItemType type) {
    return progressStream((_) async {
      try {
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

        final parsed = await compute(_parseExtensions, (
          res.body,
          repoUrl,
          type,
        ));

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
    });
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
            apkUrlOverride: apkName == null ? null : '${baseRepo}apk/$apkName',
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
          ..apkUrlOverride = repo.apkUrlOverride
          ..pkgName = repo.pkgName
          ..iconUrl = repo.iconUrl
          ..repo = repo.repo;

        changed = true;
      } else if (inst.hasUpdate == true) {
        installed[i] = inst..hasUpdate = false;
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
