import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Logger.dart';
import '../../../NetworkClient.dart';
import '../../../Settings/KvStore.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../KotatsuSourceMethods.dart';

/// Android backend for Kotatsu (<https://github.com/KotatsuApp/kotatsu-parsers>)
/// manga sources.
///
/// Unlike the APK-per-source backends, a Kotatsu "repo" is a single jar
/// bundling every parser; "installing" a source just flips its id into the
/// [_activeSourcesKey] allow-list — nothing is downloaded per source. The
/// native side (`kotatsuExtensionBridge`, `KotatsuExtensionApi` in
/// `runtimeManager/kotatsu`) enumerates every parser in that jar on
/// `getInstalledMangaExtensions`; this class does the active/available split.
class KotatsuExtensions extends Extension {
  static const _activeSourcesKey = 'kotatsu_active_sources';

  final platform = const MethodChannel('kotatsuExtensionBridge');

  @override
  String get id => 'kotatsu';

  @override
  String get name => 'Kotatsu';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/kotatsu.png";

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsNovel => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    KotatsuSource,
    (source) => KotatsuSourceMethods(
      source as KotatsuSource,
      MethodChannelBridge(platform),
    ),
  );

  @override
  DownloadablePlugin plugin = KotatsuPlugin();

  @override
  Future<bool> onInitialize() async {
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    unawaited(plugin.autoUpdate());

    final filePath = await plugin.getPath();
    await platform.invokeMethod('loadPlugin', {"path": filePath});
    await BridgeChannels.init();

    final network = DartotsuExtensionBridge.context.network;
    if (network != null) {
      await platform.invokeMethod(
        'initClient',
        jsonEncode({'dns': network.dns, 'proxy': network.proxy}),
      );
    }
    return true;
  }

  Future<Directory?> get _sourcesDir => DartotsuExtensionBridge.context
      .getDirectory(subPath: 'bridge/kotatsu', useSystemPath: false, useCustomPath: true);

  File _jarFile(Directory dir) => File('${dir.path}/plugin.jar');

  // --- repos: one shared parsers jar, not a per-source index -----------

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    if (type != ItemType.manga) return;
    try {
      final uri = Uri.tryParse(repoUrl);
      if (uri == null || !uri.hasScheme) throw Exception('Invalid repo URL');

      final repos = loadRepos(type);
      if (repos.any((r) => r.url == repoUrl)) return;

      final dir = await _sourcesDir;
      if (dir == null) throw Exception('Could not get Kotatsu plugin directory');
      if (!await dir.exists()) await dir.create(recursive: true);

      final client = MClient.init();
      final res = await client.get(uri);
      if (res.statusCode != 200) {
        throw Exception('Failed to download parsers jar (${res.statusCode})');
      }
      await _jarFile(dir).writeAsBytes(res.bodyBytes);

      final repo = Repo(url: repoUrl, name: repoNameFromUrl(repoUrl));
      final updatedRepos = List<Repo>.from(repos)..add(repo);
      saveRepos(updatedRepos, type);
      state(type).repos.value = updatedRepos;

      await fetchMangaExtensions();
      await fetchInstalledMangaExtensions();
    } catch (e) {
      Logger.log('Failed to add Kotatsu repo $repoUrl: $e');
      rethrow;
    }
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {
    try {
      final repos = loadRepos(type)
          .where((r) => r.url != repoUrl)
          .toList(growable: false);
      saveRepos(repos, type);
      state(type).repos.value = repos;

      final dir = await _sourcesDir;
      if (dir != null) {
        final jar = _jarFile(dir);
        if (await jar.exists()) await jar.delete();
      }
      setVal(_activeSourcesKey, const <String>[]);

      state(type).installed.value = const [];
      state(type).available.value = const [];
    } catch (e) {
      Logger.log('Failed to remove Kotatsu repo $repoUrl: $e');
    }
  }

  @override
  Future<List<Source>> fetchRepo(Repo repo, ItemType type) async => const [];

  // --- one shared jar -> split by the active-sources allow-list ---------

  @override
  Future<void> fetchAnimeExtensions() async {
    await super.fetchAnimeExtensions();
  }

  @override
  Future<void> fetchNovelExtensions() async {
    await super.fetchNovelExtensions();
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    await super.fetchInstalledAnimeExtensions();
  }

  @override
  Future<void> fetchInstalledNovelExtensions() async {
    await super.fetchInstalledNovelExtensions();
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    await super.fetchInstalledMangaExtensions();
    final all = await _loadAll();
    final active = _activeIds();
    state(ItemType.manga).installed.value = List.unmodifiable(
      all.where((s) => active.contains(s.id)),
    );
  }

  @override
  Future<void> fetchMangaExtensions() async {
    await super.fetchMangaExtensions();
    final all = await _loadAll();
    final active = _activeIds();
    state(ItemType.manga).available.value = List.unmodifiable(
      all.where((s) => !active.contains(s.id)),
    );
  }

  Future<List<KotatsuSource>> _loadAll() async {
    try {
      final dir = await _sourcesDir;
      if (dir == null || !await dir.exists()) return const [];
      if (!await _jarFile(dir).exists()) return const [];

      final jsonString = await platform.invokeMethod<String>(
        'getInstalledMangaExtensions',
        dir.path,
      );
      if (jsonString == null || jsonString.isEmpty) return const [];

      final List<dynamic> result = jsonDecode(jsonString);
      return result
          .map((e) => KotatsuSource.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (e) {
      Logger.log('Failed to load Kotatsu parsers: $e');
      return const [];
    }
  }

  Set<String> _activeIds() =>
      (getVal<List<String>>(_activeSourcesKey) ?? const <String>[]).toSet();

  // --- install/uninstall just toggles the allow-list --------------------

  @override
  Future<void> installSource(Source source) async {
    final ids = getVal<List<String>>(_activeSourcesKey) ?? [];
    if (!ids.contains(source.id) && source.id != null) {
      setVal(_activeSourcesKey, [...ids, source.id!]);
    }
    await fetchInstalledMangaExtensions();
    await fetchMangaExtensions();
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final ids = getVal<List<String>>(_activeSourcesKey) ?? [];
    setVal(_activeSourcesKey, ids.where((e) => e != source.id).toList());
    await fetchInstalledMangaExtensions();
    await fetchMangaExtensions();
  }

  @override
  Future<void> updateSource(Source source) async {
    // No per-source binary — refresh the shared jar's parse of it.
    await fetchInstalledMangaExtensions();
    await fetchMangaExtensions();
  }

  @override
  void detectUpdates(List<Source> available, ItemType type) {
    // One shared jar per repo; there's nothing per-source to version-compare.
  }

  @override
  Set<String> get schemes => const {};
}

class KotatsuPlugin extends DownloadablePlugin {
  @override
  String get name => "kotatsuAndroid";

  @override
  String get fileName => "kotatsuAndroid-plugin.apk";
}
