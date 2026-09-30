import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../Extensions/Extensions.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../NetworkClient.dart';
import '../../Settings/KvStore.dart';
import 'ZipValidation.dart';

/// Repo/install plumbing shared by the two Kotatsu backends (Android +
/// desktop). Kotatsu ships one shared parsers jar per repo rather than an
/// APK/JAR per source - "installing" a source just flips it in an
/// active-sources allow-list, so `addRepo`/`removeRepo`/`installSource`/
/// `uninstallSource`/`updateSource`/`detectUpdates` and the installed-source
/// cache were byte-identical between the two backends past the native
/// transport call ([loadInstalledFromNative]) and the concrete `Source`
/// subtype ([T]).
mixin KotatsuRepoBackend<T extends Source> on Extension {
  /// `getVal`/`setVal` key for this backend's active-sources allow-list -
  /// `'kotatsu_active_sources'` / `'kotatsu_desktop_active_sources'`.
  String get activeSourcesKey;

  /// Directory the parsers jar(s) live in and that the native side scans.
  Future<Directory?> get sourcesDir;

  /// Backend-specific native call to list every parser class from every jar
  /// in [dir] - the wire shape (a JSON string over a `MethodChannel` on
  /// Android vs a typed JNI call on desktop) is the only real difference
  /// between the two backends.
  Future<List<T>> loadInstalledFromNative(Directory dir);

  // The native loader (KotatsuExtensionLoader) scans the whole directory for
  // every file named "plugin.jar"/"kotatsu_plugin.jar", or any *.jar whose
  // name contains "kotatsu" - it already supports multiple parser jars side
  // by side. Each repo therefore needs a name of its own (stable and derived
  // from the repo URL, so addRepo/removeRepo/uninstall agree on it without
  // persisting anything extra) rather than a fixed "plugin.jar" every repo
  // would collide on.
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

        final dir = await sourcesDir;
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

        if (!await hasZipSignature(temp)) {
          await temp.delete();
          throw Exception(
            'This URL did not return a valid parsers jar (got something '
            'else - check the repo URL)',
          );
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

      final dir = await sourcesDir;
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

  List<T>? _cachedSources;
  Future<List<T>>? _loadingSources;

  Future<List<T>> _loadAll() {
    final cached = _cachedSources;
    if (cached != null) return Future.value(cached);
    return _loadingSources ??= _loadAllUncached();
  }

  void _invalidateSourcesCache() => _cachedSources = null;

  Future<List<T>> _loadAllUncached() async {
    try {
      final dir = await sourcesDir;
      if (dir == null || !await dir.exists()) return const [];
      // No single canonical jar path exists any more (one per repo) - skip
      // the native call only when there's nothing registered at all.
      if (loadRepos(ItemType.manga).isEmpty) return const [];

      final sources = await loadInstalledFromNative(dir);
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
      (getVal<List<String>>(activeSourcesKey) ?? const <String>[]).toSet();

  @override
  Stream<double> installSource(Source source) {
    // No download here - installing a Kotatsu source just flips it in the
    // active-list allow-list, so there's no granular progress to report.
    return progressStream((_) async {
      final ids = getVal<List<String>>(activeSourcesKey) ?? [];
      if (!ids.contains(source.id) && source.id != null) {
        setVal(activeSourcesKey, [...ids, source.id!]);
      }
      await fetchInstalledMangaExtensions();
      await fetchMangaExtensions();
    });
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final ids = getVal<List<String>>(activeSourcesKey) ?? [];
    setVal(activeSourcesKey, ids.where((e) => e != source.id).toList());
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
