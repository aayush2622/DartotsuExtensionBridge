import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../Engines/JavaEngine/Bridge/JavaBridgeFactory.dart';
import '../../../Engines/JavaEngine/Bridge/JniBridge.dart';
import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Logger.dart';
import '../../../NetworkClient.dart';
import '../../../Settings/KvStore.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../KotatsuSourceMethods.dart';

/// Desktop counterpart of `KotatsuAndroid/KotatsuExtensions.dart`. Same
/// shared-jar-plus-active-sources-allow-list model (see that file's doc
/// comment) — the only real difference is how the native side loads the
/// jar's parser classes: Android's `KotatsuExtensionApi` uses
/// `dalvik.system.DexClassLoader` directly (a real Dalvik/ART runtime is
/// available), while this backend's native `KotatsuExtensionLoader`
/// (desktopMain) runs the jar's `classes.dex` through the same dex2jar
/// conversion the other four JVM-sidecar backends already use, then loads
/// the converted jar with a normal classloader.
class KotatsuDesktopExtensions extends Extension {
  static const _activeSourcesKey = 'kotatsu_desktop_active_sources';

  @override
  String get id => 'kotatsu_desktop';

  @override
  String get name => 'Kotatsu (Desktop)';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/kotatsu.png";

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsNovel => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    KotatsuDesktopSource,
    (source) => KotatsuSourceMethods(
      source as KotatsuDesktopSource,
      JniExtensionBridge(jni),
    ),
  );

  @override
  DownloadablePlugin plugin = KotatsuDesktopPlugin();

  final JavaBridge jni = createJavaBridge();

  final _context = DartotsuExtensionBridge.context;

  @override
  Future<bool> onInitialize() async {
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    unawaited(plugin.autoUpdate());

    final filePath = await plugin.getPath();

    await BridgeChannels.init();
    await jni.init(pluginJarPath: filePath);

    final dir = await _sourcesDir;
    await jni.call<void>("initializeDesktop", {"path": dir!.path});

    if (_context.network != null) {
      await jni.call<void>(
        "initClient",
        {
          "data": jsonEncode({
            'dns': _context.network?.dns,
            'proxy': _context.network?.proxy,
          }),
        },
      );
    }
    return true;
  }

  @override
  void dispose() async {
    super.dispose();
    jni.dispose();
  }

  Future<Directory?> get _sourcesDir => _context.getDirectory(
    subPath: 'bridge/kotatsuDesktop',
    useSystemPath: false,
    useCustomPath: true,
  );

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
      if (dir == null) {
        throw Exception('Could not get Kotatsu desktop plugin directory');
      }
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
      Logger.log('Failed to add Kotatsu desktop repo $repoUrl: $e');
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
      Logger.log('Failed to remove Kotatsu desktop repo $repoUrl: $e');
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

  Future<List<KotatsuDesktopSource>> _loadAll() async {
    try {
      final dir = await _sourcesDir;
      if (dir == null || !await dir.exists()) return const [];
      if (!await _jarFile(dir).exists()) return const [];

      final result = await jni.call<List<Map<String, dynamic>>>(
        'getInstalledMangaExtensions',
        {'path': dir.path},
      );

      return result
          .map((e) => KotatsuDesktopSource.fromJson(e))
          .toList(growable: false);
    } catch (e) {
      Logger.log('Failed to load Kotatsu desktop parsers: $e');
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

class KotatsuDesktopPlugin extends DownloadablePlugin {
  @override
  String get name => "kotatsuDesktop";

  @override
  String get fileName => "kotatsuDesktop-plugin.jar";
}
