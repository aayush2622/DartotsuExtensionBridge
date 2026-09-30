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

mixin KotatsuRepoBackend<T extends Source> on Extension {
  String get activeSourcesKey;

  Future<Directory?> get sourcesDir;

  Future<List<T>> loadInstalledFromNative(Directory dir);

  File _jarFile(Directory dir, String repoUrl) =>
      File('${dir.path}/kotatsu_${_repoFileId(repoUrl)}.jar');

  String _repoFileId(String repoUrl) =>
      md5.convert(utf8.encode(repoUrl)).toString();

  @override
  Stream<double> addRepo(String repoUrl, ItemType type) {
    if (type != ItemType.manga) return const Stream<double>.empty();

    return progressStream((report) async {
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
