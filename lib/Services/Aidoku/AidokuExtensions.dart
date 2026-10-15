import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../NetworkClient.dart';
import '../Shared/SimpleInstalledSourceStore.dart';
import 'AidokuDefaults.dart';
import 'AidokuSourceMethods.dart';
import 'Manifest.dart';
import 'Models/Source.dart';

class AidokuExtensions extends Extension
    with SimpleInstalledSourceStore<AidokuSource> {
  static final _client = MClient.init();

  @override
  String get id => 'aidoku';

  @override
  String get name => 'Aidoku';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/aidoku.png";

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsNovel => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories =>
      (AidokuSource, (source) => AidokuSourceMethods(source as AidokuSource));

  @override
  AidokuSource Function(Map<String, dynamic>) get sourceFromJson =>
      AidokuSource.fromJson;

  @override
  void dispose() {
    super.dispose();
    AidokuSourceMethods.disposeAll();
  }

  @override
  Future<void> fetchMangaExtensions() async {
    await super.fetchMangaExtensions();
    manga.available.value = await fetchExtensions(ItemType.manga);
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    await super.fetchInstalledMangaExtensions();
    manga.installed.value = loadInstalled(ItemType.manga);
  }

  @override
  Stream<double> addRepo(String repoUrl, ItemType type) {
    return progressStream((_) async {
      if (type != ItemType.manga) {
        throw Exception("Aidoku only supports manga sources");
      }

      final uri = Uri.tryParse(repoUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception("Invalid repo URL");
      }

      final repos = loadRepos(type);
      if (repos.any((r) => r.url == repoUrl)) return;

      final res = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw Exception("Failed to fetch repo (${res.statusCode})");
      }

      final parsed = await compute(_parseExtensions, (res.body, repoUrl, type));

      final repo = Repo(
        url: repoUrl,
        name: repoNameFromUrl(repoUrl),
        extensions: parsed.length.toString(),
      );

      final updatedRepos = List<Repo>.from(repos)..add(repo);
      saveRepos(updatedRepos, type);
      state(type).repos.value = updatedRepos;

      saveActiveRepo(type, repo);
      state(type).activeRepo.value = repo;

      final installedIds = loadInstalled(type).map((e) => e.id).toSet();
      detectUpdates(parsed, type);
      state(type).rawAvailable.value = List.unmodifiable(parsed);
      state(type).available.value = List.unmodifiable(
        parsed.where((s) => !installedIds.contains(s.id)),
      );
    });
  }

  @override
  Future<List<Source>> fetchRepo(Repo repo, ItemType type) async {
    if (type != ItemType.manga) return const [];
    try {
      final res = await _client
          .get(Uri.parse(repo.url))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return const [];

      final extensions = await compute(_parseExtensions, (
        res.body,
        repo.url,
        type,
      ));
      await updateRepoExtensionCount(repo, type, extensions.length);
      return extensions;
    } catch (e) {
      Logger.log("Repo failed ${repo.url}: $e");
      return const [];
    }
  }

  static List<Source> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) {
    final (body, repoUrl, itemType) = args;
    if (itemType != ItemType.manga) return const [];
    return parseAidokuManifest(body, repoUrl);
  }

  @override
  Stream<double> installSource(Source source) {
    return progressStream((_) async {
      final s = source as AidokuSource;
      final type = s.itemType!;
      try {
        if (s.downloadUrl == null) throw Exception("Missing download URL");

        final res = await _client.get(Uri.parse(s.downloadUrl!));
        if (res.statusCode != 200) {
          throw Exception("Package download failed (${res.statusCode})");
        }

        s.wasmBytesBase64 = base64Encode(_extractWasm(res.bodyBytes));
        s.defaults = extractAidokuDefaults(res.bodyBytes);

        final list = loadInstalled(type)..removeWhere((e) => e.id == s.id);
        list.add(s);
        saveInstalled(list, type);
        state(type).installed.value = List.unmodifiable(list);

        final avail = state(type).available;
        avail.value = avail.value.where((e) => e.id != s.id).toList();
        detectUpdates(state(type).rawAvailable.value, type);
      } catch (e) {
        Logger.log("Install failed ${s.id}: $e");
        rethrow;
      }
    });
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as AidokuSource;
    try {
      final type = s.itemType!;
      AidokuSourceMethods.dispose(s.id!);

      final list = loadInstalled(type)..removeWhere((e) => e.id == s.id);
      saveInstalled(list, type);
      state(type).installed.value = List.unmodifiable(list);

      final installedIds = list.map((e) => e.id).toSet();
      state(type).available.value = List.unmodifiable(
        state(
          type,
        ).rawAvailable.value.where((e) => !installedIds.contains(e.id)),
      );
      detectUpdates(state(type).rawAvailable.value, type);
    } catch (e) {
      Logger.log("Uninstall failed ${s.id}: $e");
    }
  }

  @override
  Stream<double> updateSource(Source source) {
    return progressStream((_) async {
      final s = source as AidokuSource;
      final type = s.itemType!;
      if (s.downloadUrl == null) throw Exception("Missing download URL");

      final res = await _client.get(Uri.parse(s.downloadUrl!));
      if (res.statusCode != 200) {
        throw Exception("Update download failed (${res.statusCode})");
      }

      final list = loadInstalled(type);
      final i = list.indexWhere((e) => e.id == s.id);
      if (i == -1) return;

      AidokuSourceMethods.dispose(s.id!);

      list[i] = list[i]
        ..wasmBytesBase64 = base64Encode(_extractWasm(res.bodyBytes))
        ..defaults = extractAidokuDefaults(res.bodyBytes)
        ..version = s.version
        ..hasUpdate = false;
      saveInstalled(list, type);
      state(type).installed.value = List.unmodifiable(list);
    });
  }

  @override
  void detectUpdates(List<Source> available, ItemType type) {
    final installed = loadInstalled(type);
    if (installed.isEmpty || available.isEmpty) return;

    final repoMap = {for (final s in available) s.id: s};
    var changed = false;

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id];
      if (repo == null) continue;

      if (compareVersions(repo.version ?? "0", inst.version ?? "0") > 0) {
        installed[i] = inst
          ..hasUpdate = true
          ..versionLast = repo.version
          ..downloadUrl = (repo as AidokuSource).downloadUrl;
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

  static Uint8List _extractWasm(List<int> aixBytes) {
    final archive = ZipDecoder().decodeBytes(aixBytes);
    for (final file in archive.files) {
      if (file.isFile && file.name.endsWith('.wasm')) {
        return file.content;
      }
    }
    throw Exception("No .wasm module found in package");
  }

  @override
  Set<String> get schemes => {"aidoku"};

  @override
  void handleSchemes(Uri uri) {
    final url = uri.queryParameters["url"];
    if (url != null && url.isNotEmpty) {
      addRepo(url, ItemType.manga);
    }
  }
}
