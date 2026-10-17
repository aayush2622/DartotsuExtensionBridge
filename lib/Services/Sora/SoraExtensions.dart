import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../Extensions/Extensions.dart';
import '../../Extensions/RepoGuard.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../Network/MClient.dart';
import '../Shared/JsonRepoBackend.dart';
import '../Shared/SimpleInstalledSourceStore.dart';
import 'Models/Source.dart';
import 'SoraSourceMethods.dart';

class SoraExtensions extends Extension
    with SimpleInstalledSourceStore<SSource>, JsonRepoBackend {
  static final _client = MClient.init();

  @override
  http.Client get repoClient => _client;

  @override
  List<Source> Function((String body, String repoUrl, ItemType type))
  get parseRepoIsolate => _parseExtensions;

  @override
  Set<RepoFormat> get repoFormats => const {RepoFormat.sora};

  /// Names the repo after the module author, as Sora does.
  @override
  Repo repoFor(String url, String body, List<Source> sources) {
    final repo = super.repoFor(url, body, sources);
    final author = switch (_firstModule(body)) {
      {'author': final Map<String, dynamic> author} => author,
      _ => null,
    };
    if (author == null) return repo;
    return Repo(
      url: repo.url,
      name: author['name']?.toString() ?? repo.name,
      iconUrl: author['icon']?.toString(),
      extensions: repo.extensions,
    );
  }

  static Map<String, dynamic>? _firstModule(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().firstOrNull;
      }
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('sourceName')) return decoded;
        return decoded.values.whereType<Map<String, dynamic>>().firstOrNull;
      }
    } catch (_) {}
    return null;
  }

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
  SSource Function(Map<String, dynamic>) get sourceFromJson => SSource.fromJson;

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
    anime.installed.value = loadInstalled(ItemType.anime);
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    await super.fetchInstalledMangaExtensions();
    manga.installed.value = loadInstalled(ItemType.manga);
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
  Stream<double> installSource(Source source) {
    return progressStream((_) async {
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

        final installedList = loadInstalled(type);

        installedList.removeWhere((e) => e.id == s.id);
        installedList.add(installed);

        saveInstalled(installedList, type);

        state(type).installed.value = List.unmodifiable(installedList);

        final avail = state(type).available;
        avail.value = avail.value.where((e) => e.id != s.id).toList();
        final raw = state(type).rawAvailable.value;
        detectUpdates(raw, type);
      } catch (e) {
        Logger.log("Install failed ${s.id}: $e");
        rethrow;
      }
    });
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as SSource;

    try {
      final type = s.itemType!;
      final installed = loadInstalled(type);

      installed.removeWhere((e) => e.id == s.id);

      saveInstalled(installed, type);
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
  Stream<double> updateSource(Source source) {
    return progressStream((_) async {
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

        final installed = loadInstalled(type);

        final index = installed.indexWhere((e) => e.id == s.id);
        if (index == -1) return;

        installed[index] = installed[index]
          ..sourceCode = res.body
          ..version = s.version
          ..hasUpdate = false;

        saveInstalled(installed, type);

        state(type).installed.value = List.unmodifiable(installed);
      } catch (e) {
        Logger.log("Update failed ${s.id}: $e");
        rethrow;
      }
    });
  }

  @override
  void detectUpdates(List<Source> available, ItemType type) {
    final installed = loadInstalled(type);
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
      } else if (inst.hasUpdate == true) {
        installed[i] = inst..hasUpdate = false;
        changed = true;
      }
    }

    if (changed) {
      saveInstalled(installed, type);
      state(type).installed.value = List.unmodifiable(installed);
    }
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

        await addRepo(url, itemType).drain<void>();
      }
    } catch (e) {
      Logger.log("Failed to fetch repo JSON: $e");
    }
  }
}
