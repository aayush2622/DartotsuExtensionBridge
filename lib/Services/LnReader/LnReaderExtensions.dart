import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../NetworkClient.dart';
import '../../Settings/KvStore.dart';
import 'LnReaderSourceMethods.dart';
import 'Manifest.dart';
import 'Models/Source.dart';

/// Independent backend for **LNReader** plugins
/// (<https://github.com/LNReader/lnreader-plugins>).
///
/// Each plugin is a standalone JS module listed in a `plugins.min.json`
/// manifest; installing one downloads the module and stashes it on the
/// [LSource]. Novel-only — anime/manga are unsupported. The runtime and its
/// polyfills live under `Js/`; a source is driven through
/// [LnReaderSourceMethods].
class LnReaderExtensions extends Extension {
  static final _client = MClient.init();

  @override
  String get id => 'lnreader';

  @override
  String get name => 'LNReader';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/lnreader.png";

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories =>
      (LSource, (source) => LnReaderSourceMethods(source as LSource));

  @override
  void dispose() {
    super.dispose();
    LnReaderSourceMethods.disposeAll();
  }

  @override
  Future<void> fetchNovelExtensions() async {
    await super.fetchNovelExtensions();
    novel.available.value = await fetchExtensions(ItemType.novel);
  }

  @override
  Future<void> fetchInstalledNovelExtensions() async {
    await super.fetchInstalledNovelExtensions();
    novel.installed.value = _loadInstalled(ItemType.novel);
  }

  // --- repos -------------------------------------------------------------

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    try {
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
      await selectRepo(repo, type);
    } catch (e) {
      Logger.log("Failed to add repo $repoUrl: $e");
      rethrow;
    }
  }

  @override
  Future<List<Source>> fetchRepo(Repo repo, ItemType type) async {
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
    if (itemType != ItemType.novel) return const [];
    return parseLnReaderManifest(body, repoUrl);
  }

  // --- install / uninstall / update ------------------------------------

  @override
  Future<void> installSource(Source source) async {
    final s = source as LSource;
    final type = s.itemType!;
    try {
      if (s.sourceCodeUrl == null) throw Exception("Missing plugin URL");

      final res = await _client.get(Uri.parse(s.sourceCodeUrl!));
      if (res.statusCode != 200) {
        throw Exception("Plugin download failed (${res.statusCode})");
      }
      s.sourceCode = res.body;

      if (s.customCssUrl != null && s.customCssUrl!.isNotEmpty) {
        try {
          final css = await _client.get(Uri.parse(s.customCssUrl!));
          if (css.statusCode == 200) s.customCss = css.body;
        } catch (_) {}
      }

      final list = _loadInstalled(type)..removeWhere((e) => e.id == s.id);
      list.add(s);
      _saveInstalled(list, type);
      state(type).installed.value = List.unmodifiable(list);

      final avail = state(type).available;
      avail.value = avail.value.where((e) => e.id != s.id).toList();
      detectUpdates(state(type).rawAvailable.value, type);
    } catch (e) {
      Logger.log("Install failed ${s.id}: $e");
      rethrow;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as LSource;
    try {
      final type = s.itemType!;
      final list = _loadInstalled(type)..removeWhere((e) => e.id == s.id);
      _saveInstalled(list, type);
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
  Future<void> updateSource(Source source) async {
    final s = source as LSource;
    final type = s.itemType!;
    if (s.sourceCodeUrl == null) throw Exception("Missing plugin URL");

    final res = await _client.get(Uri.parse(s.sourceCodeUrl!));
    if (res.statusCode != 200) {
      throw Exception("Update download failed (${res.statusCode})");
    }

    final list = _loadInstalled(type);
    final i = list.indexWhere((e) => e.id == s.id);
    if (i == -1) return;

    list[i] = list[i]
      ..sourceCode = res.body
      ..version = s.version
      ..hasUpdate = false;
    _saveInstalled(list, type);
    state(type).installed.value = List.unmodifiable(list);
  }

  @override
  void detectUpdates(List<Source> available, ItemType type) {
    final installed = _loadInstalled(type);
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
          ..sourceCodeUrl = (repo as LSource).sourceCodeUrl;
        changed = true;
      } else if (inst.hasUpdate == true) {
        installed[i] = inst..hasUpdate = false;
        changed = true;
      }
    }

    if (changed) {
      _saveInstalled(installed, type);
      state(type).installed.value = List.unmodifiable(installed);
    }
  }

  // --- persistence -----------------------------------------------------

  List<LSource> _loadInstalled(ItemType type) {
    final encoded = getVal<List<String>>('$id-Installed-${type.name}');
    if (encoded == null || encoded.isEmpty) return [];

    final list = <LSource>[];
    for (final e in encoded) {
      try {
        list.add(LSource.fromJson(jsonDecode(e)));
      } catch (_) {}
    }
    return list;
  }

  void _saveInstalled(List<LSource> list, ItemType type) {
    setVal(
      '$id-Installed-${type.name}',
      list.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }

  // --- deep links ----------------------------------------------------

  @override
  Set<String> get schemes => {"lnreader"};

  @override
  void handleSchemes(Uri uri) {
    final url = uri.queryParameters["url"];
    if (url != null && url.isNotEmpty) {
      addRepo(url, ItemType.novel);
    }
  }
}
