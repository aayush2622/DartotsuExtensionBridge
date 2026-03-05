import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../Settings/KvStore.dart';
import '../Mangayomi/http/m_client.dart';
import 'Models/Source.dart';
import 'SoraSourceMethods.dart';

class SoraExtensions extends Extension {
  static final _client = MClient.init();

  @override
  String get id => 'sora';

  @override
  String get name => 'Sora';

  @override
  bool get supportsNovel => false;

  @override
  SourceMethods createSourceMethods(Source source) => SoraSourceMethods(source);

  @override
  Future<void> fetchAnimeExtensions() async {
    final res = await _fetchExtensions(ItemType.anime);
    getAvailableRx(ItemType.anime).value = res;
  }

  @override
  Future<void> fetchMangaExtensions() async {
    final res = await _fetchExtensions(ItemType.manga);
    getAvailableRx(ItemType.manga).value = res;
  }

  @override
  Future<void> fetchNovelExtensions() async {}

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    final installed = _loadInstalled(ItemType.anime);
    getInstalledRx(ItemType.anime).value = installed;
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    final installed = _loadInstalled(ItemType.manga);
    getInstalledRx(ItemType.manga).value = installed;
  }

  @override
  Future<void> fetchInstalledNovelExtensions() async {}

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    try {
      final uri = Uri.tryParse(repoUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception("Invalid repo URL");
      }

      final repos = _loadRepos(type);

      if (repos.any((r) => r.url == repoUrl)) {
        return;
      }

      final res = await _client.get(uri);
      if (res.statusCode != 200) {
        throw Exception("Failed to fetch repo");
      }

      final decoded = jsonDecode(res.body);

      String? repoName;
      String? repoIcon;
      Map<String, dynamic>? firstExtension;

      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        firstExtension = Map<String, dynamic>.from(decoded.first);
      } else if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('sourceName')) {
          firstExtension = decoded;
        } else {
          final values = decoded.values.whereType<Map>().toList();
          if (values.isNotEmpty) {
            firstExtension = Map<String, dynamic>.from(values.first);
          }
        }
      }

      if (firstExtension != null) {
        final author = firstExtension['author'];
        if (author is Map<String, dynamic>) {
          repoName = author['name']?.toString();
          repoIcon = author['icon']?.toString();
        }
      }

      final repo = Repo(
        url: repoUrl,
        name: repoName,
        iconUrl: repoIcon,
      );

      final updatedRepos = List<Repo>.from(repos)..add(repo);

      _saveRepos(updatedRepos, type);

      final parsed = await compute(
        _parseExtensions,
        (res.body, repoUrl, type),
      );

      final rx = getAvailableRx(type);
      final existing = rx.value;

      final merged = {
        for (final s in existing) s.id: s,
        for (final s in parsed) s.id: s,
      }.values.toList(growable: false);

      rx.value = List.unmodifiable(merged);
      getReposRx(type).value = updatedRepos;
    } catch (e) {
      Logger.log("Failed to add repo $repoUrl: $e");
      rethrow;
    }
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {
    try {
      final repos = _loadRepos(type)
          .where((r) => r.url != repoUrl)
          .toList(growable: false);

      _saveRepos(repos, type);

      final rx = getAvailableRx(type);
      rx.value = rx.value.where((s) => s.repo != repoUrl).toList();

      getReposRx(type).value = repos;
    } catch (e) {
      Logger.log("Failed to remove repo $repoUrl: $e");
    }
  }

  Future<List<Source>> _fetchExtensions(ItemType type) async {
    final repos = _loadRepos(type);
    if (repos.isEmpty) return const [];

    getReposRx(type).value = repos;

    final futures = <Future<List<Source>>>[];

    for (final repo in repos) {
      futures.add(_fetchRepo(repo, type));
    }

    final results = await Future.wait(futures);

    final allSources = <Source>[];
    for (final r in results) {
      allSources.addAll(r);
    }

    final installed = getInstalledRx(type).value;
    final installedIds = installed.map((e) => e.id).toSet();

    _detectUpdates(allSources, type);

    final filtered =
        allSources.where((s) => !installedIds.contains(s.id)).toList();

    return List.unmodifiable(filtered);
  }

  Future<List<Source>> _fetchRepo(Repo repo, ItemType type) async {
    try {
      final res = await _client.get(Uri.parse(repo.url));
      if (res.statusCode != 200) return const [];

      return compute(
        _parseExtensions,
        (res.body, repo.url, type),
      );
    } catch (e) {
      Logger.log("Repo failed ${repo.url}: $e");
      return const [];
    }
  }

  static List<Source> _parseExtensions(
      (String body, String repoUrl, ItemType itemType) args) {
    final (body, repoUrl, itemType) = args;

    try {
      final decoded = jsonDecode(body);

      Iterable<Map<String, dynamic>> extensions;

      if (decoded is List) {
        extensions = decoded.whereType<Map<String, dynamic>>();
      } else if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('sourceName')) {
          extensions = [decoded];
        } else {
          extensions = decoded.values.whereType<Map<String, dynamic>>();
        }
      } else {
        return const [];
      }

      final sources = <Source>[];

      for (final ext in extensions) {
        final type = (ext['type'] ?? '').toString().toLowerCase();

        final matches = switch (itemType) {
          ItemType.anime => type == 'anime' || type == 'movie',
          ItemType.manga => type == 'mangas',
          _ => false,
        };

        if (!matches) continue;

        sources.add(
          SSource(
            id: ext['sourceName'],
            name: ext['sourceName'],
            itemType: itemType,
            lang: ext['language'],
            version: ext['version'],
            iconUrl: ext['iconUrl'] ?? ext['iconURL'],
            baseUrl: ext['baseUrl'],
            sourceCodeUrl: ext['scriptUrl'] ?? ext['scriptURL'],
            repo: repoUrl,
          ),
        );
      }

      return sources;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> installSource(Source source) async {
    final s = source as SSource;

    try {
      if (s.sourceCodeUrl == null) {
        throw Exception("Missing sourceCodeUrl");
      }

      final res = await _client.get(Uri.parse(s.sourceCodeUrl!));
      if (res.statusCode != 200) {
        throw Exception("Failed to download extension");
      }

      final installed = SSource.fromSource(
        s,
        sourceCode: res.body,
        sourceCodeUrl: s.sourceCodeUrl,
      );

      final installedList = _loadInstalled(s.itemType!);

      installedList.removeWhere((e) => e.id == s.id);
      installedList.add(installed);

      _saveInstalled(installedList, s.itemType!);

      getInstalledRx(s.itemType!).value = List.unmodifiable(installedList);

      final avail = getAvailableRx(s.itemType!);
      avail.value = avail.value.where((e) => e.id != s.id).toList();
    } catch (e) {
      Logger.log("Install failed ${s.id}: $e");
      rethrow;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as SSource;

    try {
      final type = s.itemType!;
      final installed = _loadInstalled(type);

      installed.removeWhere((e) => e.id == s.id);

      _saveInstalled(installed, type);

      getInstalledRx(type).value = List.unmodifiable(installed);

      final availRx = getAvailableRx(type);
      final avail = List<Source>.from(availRx.value);

      avail.removeWhere((e) => e.id == s.id);

      avail.add(
        SSource.fromSource(
          s,
          sourceCodeUrl: s.sourceCodeUrl,
          sourceCode: null,
        ),
      );

      availRx.value = List.unmodifiable(avail);
    } catch (e) {
      Logger.log("Uninstall failed ${s.id}: $e");
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    final s = source as SSource;

    try {
      if (s.sourceCodeUrl == null) {
        throw Exception("Missing sourceCodeUrl");
      }

      final res = await _client.get(Uri.parse(s.sourceCodeUrl!));
      if (res.statusCode != 200) {
        throw Exception("Failed to download update");
      }

      final installed = _loadInstalled(s.itemType!);

      final index = installed.indexWhere((e) => e.id == s.id);
      if (index == -1) return;

      final updated = installed[index].copyWith(
        sourceCode: res.body,
        version: s.version,
        versionLast: s.version,
        hasUpdate: false,
      );

      installed[index] = updated;

      _saveInstalled(installed, s.itemType!);

      getInstalledRx(s.itemType!).value = List.unmodifiable(installed);
    } catch (e) {
      Logger.log("Update failed ${s.id}: $e");
      rethrow;
    }
  }

  void _detectUpdates(List<Source> available, ItemType type) {
    final installed = _loadInstalled(type);
    if (installed.isEmpty) return;

    final repoMap = {
      for (final s in available) s.id: s,
    };

    bool changed = false;

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id];
      if (repo == null) continue;

      if (compareVersions(repo.version ?? "0", inst.version ?? "0") > 0) {
        installed[i] = inst.copyWith(
          hasUpdate: true,
          versionLast: repo.version,
        );
        changed = true;
      }
    }

    if (changed) {
      _saveInstalled(installed, type);
      getInstalledRx(type).value = List.unmodifiable(installed);
    }
  }

  List<Repo> _loadRepos(ItemType type) {
    final encoded = getVal<List<String>>('sora${type.name}Repos');
    if (encoded == null || encoded.isEmpty) return const [];

    return encoded
        .map((e) => Repo.fromJson(jsonDecode(e)))
        .toList(growable: false);
  }

  void _saveRepos(List<Repo> repos, ItemType type) {
    final key = 'sora${type.name}Repos';

    setVal(
      key,
      repos.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }

  List<SSource> _loadInstalled(ItemType type) {
    final encoded = getVal<List<String>>('soraInstalled${type.name}');
    if (encoded == null || encoded.isEmpty) return [];

    return encoded
        .map((e) {
          try {
            return SSource.fromJson(jsonDecode(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<SSource>()
        .toList();
  }

  void _saveInstalled(List<SSource> list, ItemType type) {
    final key = 'soraInstalled${type.name}';

    setVal(
      key,
      list.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }
}
