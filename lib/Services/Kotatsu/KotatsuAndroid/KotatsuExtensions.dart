import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Logger.dart';
import '../../../NetworkClient.dart';
import '../../../Settings/KvStore.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../KotatsuSourceMethods.dart';

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

  Future<Directory?> get _sourcesDir =>
      DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/kotatsu',
        useSystemPath: false,
        useCustomPath: true,
      );

  // The native loader (KotatsuExtensionLoader) scans the whole directory
  // for every file named "plugin.jar"/"kotatsu_plugin.jar", or any *.jar
  // whose name contains "kotatsu" - it already supports multiple parser
  // jars side by side. Each repo therefore needs a name of its own (stable
  // and derived from the repo URL, so addRepo/removeRepo/uninstall agree on
  // it without persisting anything extra) rather than the fixed
  // "plugin.jar" every repo used to collide on, which made adding a second
  // repo silently overwrite the first repo's jar and made removeRepo delete
  // whichever jar happened to be on disk regardless of which repo it was
  // asked to remove.
  File _jarFile(Directory dir, String repoUrl) =>
      File('${dir.path}/kotatsu_${_repoFileId(repoUrl)}.jar');

  String _repoFileId(String repoUrl) =>
      md5.convert(utf8.encode(repoUrl)).toString();

  @override
  Stream<double> addRepo(String repoUrl, ItemType type) {
    if (type != ItemType.manga) return const Stream<double>.empty();

    return progressStream((report) async {
      // Kotatsu's shared parsers jar can be several MB - unlike a plain
      // buffered client.get(), stream it so the UI can show real progress
      // (state(type).loadingRepo / repoLoadProgress, and now this stream)
      // instead of hanging with no feedback until the whole body has
      // arrived.
      state(type).loadingRepo.value = true;
      state(type).repoLoadProgress.value = null;

      try {
        final uri = Uri.tryParse(repoUrl);
        if (uri == null || !uri.hasScheme) {
          throw Exception('Invalid repo URL');
        }

        final repos = loadRepos(type);
        if (repos.any((r) => r.url == repoUrl)) return;

        final dir = await _sourcesDir;
        if (dir == null) {
          throw Exception('Could not get Kotatsu plugin directory');
        }
        if (!await dir.exists()) await dir.create(recursive: true);

        final client = MClient.init();
        final response = await client.send(http.Request('GET', uri));

        if (response.statusCode != 200) {
          await response.stream.drain<void>();
          throw Exception(
            'Failed to download parsers jar (${response.statusCode})',
          );
        }

        final jarFile = _jarFile(dir, repoUrl);
        final temp = File('${jarFile.path}.tmp');
        final sink = temp.openWrite();
        final total = response.contentLength;
        var received = 0;

        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (total != null && total > 0) {
              final fraction = received / total;
              state(type).repoLoadProgress.value = fraction;
              report(fraction);
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }

        try {
          await temp.rename(jarFile.path);
        } on FileSystemException {
          // Windows won't rename onto an existing file - fall back to
          // replace.
          await temp.copy(jarFile.path);
          await temp.delete();
        }

        final repo = Repo(url: repoUrl, name: repoNameFromUrl(repoUrl));
        final updatedRepos = List<Repo>.from(repos)..add(repo);
        saveRepos(updatedRepos, type);
        state(type).repos.value = updatedRepos;
        _invalidateSourcesCache();

        await fetchMangaExtensions();
        await fetchInstalledMangaExtensions();
      } catch (e) {
        Logger.log('Failed to add Kotatsu repo $repoUrl: $e');
        rethrow;
      } finally {
        state(type).loadingRepo.value = false;
        state(type).repoLoadProgress.value = null;
      }
    });
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {
    try {
      final repos = loadRepos(
        type,
      ).where((r) => r.url != repoUrl).toList(growable: false);
      saveRepos(repos, type);
      state(type).repos.value = repos;

      final dir = await _sourcesDir;
      if (dir != null) {
        final jar = _jarFile(dir, repoUrl);
        if (await jar.exists()) await jar.delete();
      }
      _invalidateSourcesCache();

      // Re-derive installed/available from what's left on disk instead of
      // blanking both lists and clearing every active-source toggle - with
      // per-repo jar files, removing one repo must not touch sources that
      // belong to a different, still-installed repo.
      await fetchInstalledMangaExtensions();
      await fetchMangaExtensions();
    } catch (e) {
      Logger.log('Failed to remove Kotatsu repo $repoUrl: $e');
    }
  }

  @override
  Future<List<Source>> fetchRepo(Repo repo, ItemType type) async => const [];

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

  List<KotatsuSource>? _cachedSources;
  Future<List<KotatsuSource>>? _loadingSources;

  Future<List<KotatsuSource>> _loadAll() {
    final cached = _cachedSources;
    if (cached != null) return Future.value(cached);
    return _loadingSources ??= _loadAllUncached();
  }

  void _invalidateSourcesCache() => _cachedSources = null;

  Future<List<KotatsuSource>> _loadAllUncached() async {
    try {
      final dir = await _sourcesDir;
      if (dir == null || !await dir.exists()) return const [];
      // No single canonical jar path exists any more (one per repo) - skip
      // the native call only when there's nothing registered at all.
      if (loadRepos(ItemType.manga).isEmpty) return const [];

      final jsonString = await platform.invokeMethod<String>(
        'getInstalledMangaExtensions',
        dir.path,
      );
      if (jsonString == null || jsonString.isEmpty) return const [];

      final List<dynamic> result = jsonDecode(jsonString);
      final sources = result
          .map((e) => KotatsuSource.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);

      _cachedSources = sources;
      return sources;
    } catch (e) {
      Logger.log('Failed to load Kotatsu parsers: $e');
      return const [];
    } finally {
      _loadingSources = null;
    }
  }

  Set<String> _activeIds() =>
      (getVal<List<String>>(_activeSourcesKey) ?? const <String>[]).toSet();

  @override
  Stream<double> installSource(Source source) {
    // No download here - installing a Kotatsu source just flips it in the
    // active-list allow-list, so there's no granular progress to report.
    return progressStream((_) async {
      final ids = getVal<List<String>>(_activeSourcesKey) ?? [];
      if (!ids.contains(source.id) && source.id != null) {
        setVal(_activeSourcesKey, [...ids, source.id!]);
      }
      await fetchInstalledMangaExtensions();
      await fetchMangaExtensions();
    });
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final ids = getVal<List<String>>(_activeSourcesKey) ?? [];
    setVal(_activeSourcesKey, ids.where((e) => e != source.id).toList());
    await fetchInstalledMangaExtensions();
    await fetchMangaExtensions();
  }

  @override
  Stream<double> updateSource(Source source) {
    return progressStream((_) async {
      await fetchInstalledMangaExtensions();
      await fetchMangaExtensions();
    });
  }

  @override
  void detectUpdates(List<Source> available, ItemType type) {}

  @override
  Set<String> get schemes => const {};
}

class KotatsuPlugin extends DownloadablePlugin {
  @override
  String get name => "kotatsuAndroid";

  @override
  String get fileName => "kotatsuAndroid-plugin.apk";
}
