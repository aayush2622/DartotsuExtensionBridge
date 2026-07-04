import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../NetworkClient.dart';
import '../../Settings/KvStore.dart';
import 'MangayomiSourceMethods.dart';
import 'Models/Source.dart';
import 'Util/lib.dart';

class MangayomiExtensions extends Extension {
  static final _client = MClient.init();

  @override
  String get id => 'mangayomi';

  @override
  String get name => 'Mangayomi';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/mangayomi.png";
  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories =>
      (MSource, (source) => MangayomiSourceMethods(source as MSource));

  @override
  Future<void> fetchAnimeExtensions() async {
    await super.fetchAnimeExtensions();
    anime.available.value = await fetchExtensions(ItemType.anime);
  }

  @override
  Future<void> fetchMangaExtensions() async {
    await super.fetchMangaExtensions();
    manga.available.value = await fetchExtensions(ItemType.manga);
  }

  @override
  Future<void> fetchNovelExtensions() async {
    await super.fetchNovelExtensions();
    novel.available.value = await fetchExtensions(ItemType.novel);
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    await super.fetchInstalledAnimeExtensions();
    anime.installed.value = _loadInstalled(ItemType.anime);
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    await super.fetchInstalledMangaExtensions();
    manga.installed.value = _loadInstalled(ItemType.manga);
  }

  @override
  Future<void> fetchInstalledNovelExtensions() async {
    await super.fetchInstalledNovelExtensions();
    novel.installed.value = _loadInstalled(ItemType.novel);
  }

  @override
  Future<void> installSource(Source source) async {
    final m = source as MSource;
    final type = m.itemType!;
    try {
      final res = await _client.get(Uri.parse(m.sourceCodeUrl!));

      if (res.statusCode != 200) {
        throw Exception("Extension download failed");
      }

      final installed = m
        ..sourceCode = res.body
        ..headers = jsonEncode(getExtensionService(m).getHeaders());

      final list = _loadInstalled(type);

      list.removeWhere((e) => e.id == m.id);
      list.add(installed);

      _saveInstalled(list, type);

      state(type).installed.value = List.unmodifiable(list);

      final avail = state(type).available;
      avail.value = avail.value.where((e) => e.id != m.id).toList();
      final raw = state(type).rawAvailable.value;
      detectUpdates(raw, type);
    } catch (e) {
      Logger.log("Install failed ${m.id}: $e");
      rethrow;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as MSource;

    try {
      final type = s.itemType!;
      final installed = _loadInstalled(type);

      installed.removeWhere((e) => e.id == s.id);

      _saveInstalled(installed, type);
      state(type).installed.value = List.unmodifiable(installed);

      final raw = state(type).rawAvailable.value;
      final installedIds = installed.map((e) => e.id).toSet();

      state(type).available.value = List.unmodifiable(
        raw.where((e) => !installedIds.contains(e.id)),
      );
      detectUpdates(raw, type);
    } catch (e) {
      Logger.log("Uninstall failed ${s.id}: $e");
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    final s = source as MSource;
    final type = s.itemType!;
    final res = await _client.get(Uri.parse(s.sourceCodeUrl!));

    if (res.statusCode != 200) {
      throw Exception("Update download failed");
    }

    final installed = _loadInstalled(type);

    final index = installed.indexWhere((e) => e.id == s.id);
    if (index == -1) return;

    installed[index] = installed[index]
      ..sourceCode = res.body
      ..version = s.version
      ..hasUpdate = false;

    _saveInstalled(installed, type);

    state(type).installed.value = List.unmodifiable(installed);
  }

  @override
  void detectUpdates(List<Source> available, ItemType type) {
    final installed = _loadInstalled(type);

    final repoMap = {for (var s in available) s.id: s};

    bool changed = false;

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id];

      if (repo == null) continue;

      if (compareVersions(repo.version ?? "0", inst.version ?? "0") > 0) {
        installed[i] = inst
          ..hasUpdate = true
          ..versionLast = repo.version;
        changed = true;
      }
    }

    if (changed) {
      _saveInstalled(installed, type);
      state(type).installed.value = List.unmodifiable(installed);
    }
  }

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    try {
      final uri = Uri.tryParse(repoUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception("Invalid URL");
      }

      final repos = loadRepos(type);

      if (repos.any((r) => r.url == repoUrl)) {
        return;
      }

      final res = await _client.get(uri);
      if (res.statusCode != 200) {
        throw Exception("Failed to fetch repo");
      }

      final repo = Repo(name: repoNameFromUrl(repoUrl), url: repoUrl);
      final updatedRepos = List<Repo>.from(repos)..add(repo);

      saveRepos(updatedRepos, type);
      state(type).repos.value = updatedRepos;
      await selectRepo(repo, type);
    } catch (e) {
      Logger.log("Failed to add repo $repoUrl: $e");
      rethrow;
    }
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

  static List<Source> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) {
    final (body, repoUrl, itemType) = args;

    final decoded = jsonDecode(body);

    if (decoded is! List) return const [];

    final sources = <Source>[];

    for (final e in decoded) {
      final ext = Map<String, dynamic>.from(e);

      sources.add(MSource.fromJson(ext)..repo = repoUrl);
    }

    return sources.where((s) => s.itemType == itemType).toList(growable: false);
  }

  List<MSource> _loadInstalled(ItemType type) {
    final encoded = getVal<List<String>>('$id-Installed-${type.name}');
    if (encoded == null) return [];

    return encoded.map((e) => MSource.fromJson(jsonDecode(e))).toList();
  }

  void _saveInstalled(List<MSource> list, ItemType type) {
    setVal(
      '$id-Installed-${type.name}',
      list.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Set<String> get schemes => {"dar", "anymex", "sugoireads", "mangayomi"};

  @override
  void handleSchemes(Uri uri) {
    final qp = uri.queryParameters;

    if (uri.host == "add-repo") {
      final repoUrl = qp["repo_url"] ?? qp['url'] ?? qp['anime_url'];
      final mangaUrl = qp["manga_url"];
      final novelUrl = qp["novel_url"];

      if (mangaUrl != null && mangaUrl.isNotEmpty) {
        addRepo(mangaUrl, ItemType.manga);
      }

      if (novelUrl != null && novelUrl.isNotEmpty) {
        addRepo(novelUrl, ItemType.novel);
      }

      if (repoUrl != null && repoUrl.isNotEmpty) {
        addRepo(repoUrl, ItemType.anime);
      }
    }
  }
}
