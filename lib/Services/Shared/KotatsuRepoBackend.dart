import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../Extensions/Extensions.dart';
import '../../Extensions/RepoGuard.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../Network/MClient.dart';
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
  Set<RepoFormat> get repoFormats => const {RepoFormat.kotatsu};

  /// A Kotatsu repo is a parsers jar; adding one downloads it.
  @override
  Stream<double> addRepo(String repoUrl, ItemType type) =>
      addRepoTask(repoUrl, type, (url, report) async {
        final dir = await sourcesDir;
        if (dir == null) {
          throw Exception('Could not get Kotatsu plugin directory');
        }
        if (!await dir.exists()) await dir.create(recursive: true);

        final jarFile = _jarFile(dir, url);
        final temp = File('${jarFile.path}.tmp');
        await _download(url, temp, (fraction) {
          state(type).repoLoadProgress.value = fraction;
          report(fraction);
        });

        if (!await hasZipSignature(temp)) {
          final head = await temp
              .openRead(0, 65536)
              .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
          await temp.delete();
          throw invalidRepo(type, body: head, url: url);
        }

        try {
          await temp.rename(jarFile.path);
        } on FileSystemException {
          await temp.copy(jarFile.path);
          await temp.delete();
        }

        final repos = [
          ...loadRepos(type),
          Repo(url: url, name: repoNameFromUrl(url)),
        ];
        saveRepos(repos, type);
        state(type).repos.value = List.unmodifiable(repos);
        _invalidateSourcesCache();

        await fetchMangaExtensions();
        await fetchInstalledMangaExtensions();
      });

  Future<void> _download(
    String url,
    File target,
    void Function(double fraction) onProgress,
  ) async {
    final http.StreamedResponse response;
    try {
      response = await MClient.download().send(
        http.Request('GET', Uri.parse(url)),
      );
    } catch (e) {
      throw RepoException(
        'Could not reach the repository: ${Extension.describeError(e)}',
      );
    }

    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw RepoException(
        response.statusCode == 404
            ? 'Nothing was found at this link (HTTP 404). Check the repository URL.'
            : 'The repository returned an error (HTTP ${response.statusCode}).',
      );
    }

    final sink = target.openWrite();
    final total = response.contentLength;
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) onProgress(received / total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
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
