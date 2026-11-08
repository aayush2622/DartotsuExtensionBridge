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

const _localRepoPrefix = 'local:';

mixin KotatsuRepoBackend<T extends Source> on Extension {
  String get activeSourcesKey;

  Future<Directory?> get sourcesDir;

  Future<List<T>> loadInstalledFromNative(Directory dir);

  /// Every repository keeps its jar (and what the loader caches next to it)
  /// in a folder of its own, so a scan only ever sees the active repository's
  /// sources.
  Directory _repoDir(Directory dir, String repoUrl) =>
      Directory('${dir.path}/${_repoFileId(repoUrl)}');

  File _jarFile(Directory dir, String repoUrl) => File(
    '${_repoDir(dir, repoUrl).path}/kotatsu_${_repoFileId(repoUrl)}.jar',
  );

  /// Moves a jar saved by an older version (next to the other repositories)
  /// into its folder.
  Future<void> _adopt(Directory dir, String repoUrl) async {
    final legacy = File('${dir.path}/kotatsu_${_repoFileId(repoUrl)}.jar');
    if (!await legacy.exists()) return;
    final target = _jarFile(dir, repoUrl);
    await target.parent.create(recursive: true);
    if (await target.exists()) {
      await legacy.delete();
      return;
    }
    try {
      await legacy.rename(target.path);
    } on FileSystemException {
      await legacy.copy(target.path);
      await legacy.delete();
    }
  }

  Repo? _activeRepo() {
    final repos = loadRepos(ItemType.manga);
    if (repos.isEmpty) return null;
    return loadActiveRepo(ItemType.manga) ?? repos.first;
  }

  void _syncRepoState() {
    final s = state(ItemType.manga);
    s.repos.value = List.unmodifiable(loadRepos(ItemType.manga));
    final active = _activeRepo();
    s.activeRepo.value = active;
    if (active != null) saveActiveRepo(ItemType.manga, active);
  }

  void _select(Repo repo) {
    saveActiveRepo(ItemType.manga, repo);
    state(ItemType.manga).activeRepo.value = repo;
    _invalidateSourcesCache();
  }

  /// Switching repository shows only the new one's sources.
  @override
  Future<void> selectRepo(Repo repo, ItemType type) async {
    _select(repo);
    await fetchInstalledMangaExtensions();
    await fetchMangaExtensions();
  }

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
        await jarFile.parent.create(recursive: true);
        final temp = File('${jarFile.path}.tmp');
        final source = await resolveJarUrl(url);
        final validator = await _download(source, temp, (fraction) {
          state(type).repoLoadProgress.value = fraction;
          report(fraction);
        });
        if (validator != null) setVal(_validatorKey(url), validator);

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

        final repo = Repo(url: url, name: repoNameFromUrl(url));
        final repos = [...loadRepos(type), repo];
        saveRepos(repos, type);
        state(type).repos.value = List.unmodifiable(repos);
        _select(repo);

        await fetchMangaExtensions();
        await fetchInstalledMangaExtensions();
      });

  /// A GitHub repository, releases or release page is resolved to the `.jar`
  /// asset of its (latest) release; direct links are used as they are.
  Future<String> resolveJarUrl(String url) async {
    final uri = Uri.parse(url);
    if (uri.host != 'github.com' || uri.path.toLowerCase().endsWith('.jar')) {
      return url;
    }
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.length < 2) return url;
    if (seg.length >= 4 && seg[2] == 'releases' && seg[3] == 'download') {
      return url;
    }
    final base = 'https://api.github.com/repos/${seg[0]}/${seg[1]}';
    final tag = seg.length >= 5 && seg[2] == 'releases' && seg[3] == 'tag'
        ? seg[4]
        : null;
    final jar =
        await _jarAsset(
          tag != null ? '$base/releases/tags/$tag' : '$base/releases/latest',
        ) ??
        (tag == null ? await _jarAsset('$base/releases?per_page=10') : null);
    if (jar == null) {
      throw RepoException(
        'No .jar file was found in the releases of ${seg[0]}/${seg[1]}. '
        'Use the direct link to the .jar file.',
      );
    }
    return jar;
  }

  Future<String?> _jarAsset(String api) async {
    try {
      final res = await MClient.download()
          .get(
            Uri.parse(api),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      final releases = body is List ? body : [body];
      for (final release in releases) {
        final assets = (release as Map)['assets'];
        if (assets is! List) continue;
        final jars = [
          for (final a in assets)
            if ((a['name'] as String).toLowerCase().endsWith('.jar') &&
                a['browser_download_url'] is String)
              a,
        ];
        if (jars.isEmpty) continue;
        jars.sort((a, b) {
          int rank(String n) =>
              RegExp(r'raw|source|javadoc', caseSensitive: false).hasMatch(n)
              ? 1
              : 0;
          return rank(a['name']).compareTo(rank(b['name']));
        });
        return jars.first['browser_download_url'] as String;
      }
    } catch (e) {
      Logger.log('Could not read the releases at $api: $e');
    }
    return null;
  }

  @override
  List<String> get importExtensions => const ['jar'];

  /// Adds a parsers jar picked from the device as a repository of its own.
  @override
  Stream<double> importFile(String path, ItemType type) {
    return progressStream((report) async {
      final source = File(path);
      if (!await source.exists()) {
        throw const RepoException('That file does not exist any more.');
      }
      if (!await hasZipSignature(source)) {
        throw const RepoException('This is not a .jar file.');
      }
      final dir = await sourcesDir;
      if (dir == null) {
        throw Exception('Could not get Kotatsu plugin directory');
      }
      if (!await dir.exists()) await dir.create(recursive: true);

      final fileName = source.uri.pathSegments.last;
      final url = '$_localRepoPrefix$fileName';
      final jarFile = _jarFile(dir, url);
      await jarFile.parent.create(recursive: true);
      await source.copy(jarFile.path);
      report(0.5);

      final repo = Repo(url: url, name: fileName);
      final repos = [...loadRepos(type).where((r) => r.url != url), repo];
      saveRepos(repos, type);
      state(type).repos.value = List.unmodifiable(repos);
      _select(repo);

      await fetchMangaExtensions();
      await fetchInstalledMangaExtensions();
    });
  }

  String _validatorKey(String repoUrl) =>
      'kotatsu_validator_${_repoFileId(repoUrl)}';

  /// Downloads [url] into [target]. With a [validator] from an earlier
  /// download the server can answer "not modified", and then nothing is
  /// downloaded and null is returned; otherwise the new validator ('' when
  /// the server sends none).
  Future<String?> _download(
    String url,
    File target,
    void Function(double fraction) onProgress, {
    String? validator,
  }) async {
    final http.StreamedResponse response;
    try {
      final request = http.Request('GET', Uri.parse(url));
      if (validator != null && validator.isNotEmpty) {
        request.headers[validator.startsWith('W/') || validator.startsWith('"')
                ? 'If-None-Match'
                : 'If-Modified-Since'] =
            validator;
      }
      response = await MClient.download().send(request);
    } catch (e) {
      throw RepoException(
        'Could not reach the repository: ${Extension.describeError(e)}',
      );
    }

    if (response.statusCode == 304) {
      await response.stream.drain<void>();
      return null;
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
    return response.headers['etag'] ?? response.headers['last-modified'] ?? '';
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
        final folder = _repoDir(dir, repoUrl);
        if (await folder.exists()) await folder.delete(recursive: true);
        final legacy = File('${dir.path}/kotatsu_${_repoFileId(repoUrl)}.jar');
        if (await legacy.exists()) await legacy.delete();
      }
      final active = loadActiveRepo(type);
      if (repos.isEmpty) {
        setVal('$id${type.name}ActiveRepo', null);
        state(type).activeRepo.value = null;
      } else if (active == null || active.url == repoUrl) {
        saveActiveRepo(type, repos.first);
        state(type).activeRepo.value = repos.first;
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
    _syncRepoState();
    final all = await _loadAll();
    final active = _activeIds();
    state(ItemType.manga).installed.value = List.unmodifiable(
      all.where((s) => active.contains(s.id)),
    );
  }

  @override
  Future<void> fetchMangaExtensions() async {
    await super.fetchMangaExtensions();
    _syncRepoState();
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
      final repo = _activeRepo();
      if (repo == null) return const [];
      await _adopt(dir, repo.url);
      final folder = _repoDir(dir, repo.url);
      if (!await folder.exists()) return const [];

      final sources = await loadInstalledFromNative(folder);
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
    return progressStream((report) async {
      await _refreshJars(report);
      await fetchInstalledMangaExtensions();
      await fetchMangaExtensions();
    });
  }

  /// Downloads a repository's jar again only when the server says it changed
  /// (an ETag / Last-Modified check, so an unchanged jar costs one tiny
  /// request instead of the whole file).
  Future<void> _refreshJars(void Function(double) report) async {
    final dir = await sourcesDir;
    if (dir == null) return;
    var changed = false;
    for (final repo in loadRepos(ItemType.manga)) {
      if (repo.url.startsWith(_localRepoPrefix)) continue;
      await _adopt(dir, repo.url);
      final jarFile = _jarFile(dir, repo.url);
      final temp = File('${jarFile.path}.tmp');
      try {
        final validator = await _download(
          await resolveJarUrl(repo.url),
          temp,
          (fraction) => report(fraction),
          validator: await jarFile.exists()
              ? getVal<String>(_validatorKey(repo.url))
              : null,
        );
        if (validator == null) continue;
        if (!await hasZipSignature(temp)) {
          await temp.delete();
          continue;
        }
        await temp.rename(jarFile.path);
        setVal(_validatorKey(repo.url), validator);
        changed = true;
      } catch (e) {
        Logger.log('Could not refresh the Kotatsu repo ${repo.url}: $e');
        if (await temp.exists()) await temp.delete();
      }
    }
    if (changed) _invalidateSourcesCache();
  }

  @override
  void detectUpdates(List<Source> available, ItemType type) {}

  @override
  Set<String> get schemes => const {};
}
