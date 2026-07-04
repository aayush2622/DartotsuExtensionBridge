import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../NetworkClient.dart';
import '../../Settings/KvStore.dart';
import 'Models/Source.dart';
import 'SoraSourceMethods.dart';

class SoraExtensions extends Extension {
  static final _client = MClient.init();

  @override
  String get id => 'sora';

  @override
  String get name => 'Sora';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/sora.png";
  @override
  bool get supportsNovel => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories =>
      (SSource, (source) => SoraSourceMethods(source as SSource));

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
  Future<void> addRepo(String repoUrl, ItemType type) async {
    try {
      final uri = Uri.tryParse(repoUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception("Invalid repo URL");
      }

      final repos = loadRepos(type);

      if (repos.any((r) => r.url == repoUrl)) {
        return;
      }

      final res = await _client.get(uri);
      if (res.statusCode != 200) {
        throw Exception("Failed to fetch repo");
      }

      final decoded = jsonDecode(res.body);

      final parsed = await compute(_parseExtensions, (res.body, repoUrl, type));

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
        name: repoName ?? repoNameFromUrl(repoUrl),
        iconUrl: repoIcon,
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
  }

  @override
  Future<List<Source>> fetchRepo(Repo repo, ItemType type) async {
    try {
      final res = await _client.get(Uri.parse(repo.url));
      if (res.statusCode == 200) {
        var extensions = await compute(_parseExtensions, (
          res.body,
          repo.url,
          type,
        ));
        await updateRepoExtensionCount(repo, type, extensions.length);

        return extensions;
      }
      return [];
    } catch (e) {
      Logger.log("Repo failed ${repo.url}: $e");
      return const [];
    }
  }

  static List<Source> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) {
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
          extensions = decoded.values.cast<Map<String, dynamic>>();
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
            id: '${ext['sourceName']}@$repoUrl',
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
      final type = s.itemType!;
      if (s.sourceCodeUrl == null) {
        throw Exception("Missing sourceCodeUrl");
      }

      final res = await _client.get(Uri.parse(s.sourceCodeUrl!));
      if (res.statusCode != 200) {
        throw Exception("Failed to download extension");
      }

      final installed = s..sourceCode = res.body;

      final installedList = _loadInstalled(type);

      installedList.removeWhere((e) => e.id == s.id);
      installedList.add(installed);

      _saveInstalled(installedList, type);

      state(type).installed.value = List.unmodifiable(installedList);

      final avail = state(type).available;
      avail.value = avail.value.where((e) => e.id != s.id).toList();
      final raw = state(type).rawAvailable.value;
      detectUpdates(raw, type);
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
    final s = source as SSource;
    final type = s.itemType!;
    try {
      if (s.sourceCodeUrl == null) {
        throw Exception("Missing sourceCodeUrl");
      }

      final res = await _client.get(Uri.parse(s.sourceCodeUrl!));
      if (res.statusCode != 200) {
        throw Exception("Failed to download update");
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
    } catch (e) {
      Logger.log("Update failed ${s.id}: $e");
      rethrow;
    }
  }

  @override
  void detectUpdates(List<Source> available, ItemType type) {
    final installed = _loadInstalled(type);
    if (installed.isEmpty || available.isEmpty) return;

    final repoMap = {for (final s in available) s.id: s};

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

  List<SSource> _loadInstalled(ItemType type) {
    final encoded = getVal<List<String>>('$id-Installed-${type.name}');
    if (encoded == null || encoded.isEmpty) return [];

    final list = <SSource>[];

    for (final e in encoded) {
      try {
        list.add(SSource.fromJson(jsonDecode(e)));
      } catch (_) {}
    }

    return list;
  }

  void _saveInstalled(List<SSource> list, ItemType type) {
    final key = '$id-Installed-${type.name}';

    setVal(
      key,
      list.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }

  @override
  Set<String> get schemes => {"sora"};

  @override
  void handleSchemes(Uri uri) {
    final url = uri.queryParameters["url"];
    if (url != null && url.isNotEmpty) {
      _fetchAndAddRepo(url);
    }
  }

  Future<void> _fetchAndAddRepo(String url) async {
    try {
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final type = json["type"] as String?;

        final itemType = switch (type?.toLowerCase()) {
          "anime" => ItemType.anime,
          "manga" => ItemType.manga,
          _ => ItemType.anime,
        };

        await addRepo(url, itemType);
      }
    } catch (e) {
      Logger.log("Failed to fetch repo JSON: $e");
    }
  }
}
