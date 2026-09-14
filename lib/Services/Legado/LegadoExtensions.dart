import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../NetworkClient.dart';
import '../../Settings/KvStore.dart';
import 'LegadoSourceMethods.dart';
import 'Models/LegadoSource.dart';

/// Independent backend for **Legado / 阅读** book sources
/// (<https://github.com/gedoor/legado>).
///
/// A repo is a JSON array (or `{sources|data: [...]}`) of "书源" objects, each
/// carrying its own HTML parse rules — there is no plugin binary, so
/// installing a source just stashes its JSON. Everything runs pure-Dart via
/// [LegadoSourceMethods] + `LegadoRuleEngine`. Novel-only.
class LegadoExtensions extends Extension {
  static final _client = MClient.init();

  @override
  String get id => 'legado';

  @override
  String get name => 'Legado';

  @override
  String get icon =>
      'https://raw.githubusercontent.com/gedoor/legado/master/app/src/main/'
      'res/mipmap-xxxhdpi/ic_launcher.png';

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories =>
      (LegadoSource, (source) => LegadoSourceMethods(source as LegadoSource));

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

  // --- repos -----------------------------------------------------------

  @override
  Stream<double> addRepo(String repoUrl, ItemType type) {
    if (type != ItemType.novel) return const Stream<double>.empty();

    return progressStream((_) async {
      try {
        final uri = Uri.tryParse(repoUrl);
        if (uri == null || !uri.hasScheme) {
          throw Exception('Invalid repo URL');
        }

        final repos = loadRepos(type);
        if (repos.any((r) => r.url == repoUrl)) return;

        final res = await _client.get(uri).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          throw Exception('Failed to fetch repo (${res.statusCode})');
        }

        final body = utf8.decode(res.bodyBytes, allowMalformed: true);
        final parsed = await compute(_parseExtensions, (body, repoUrl, type));

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
        Logger.log('Failed to add Legado repo $repoUrl: $e');
        rethrow;
      }
    });
  }

  @override
  Future<List<Source>> fetchRepo(Repo repo, ItemType type) async {
    if (type != ItemType.novel) return const [];
    try {
      final res = await _client
          .get(Uri.parse(repo.url))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return const [];

      final body = utf8.decode(res.bodyBytes, allowMalformed: true);
      final extensions = await compute(_parseExtensions, (
        body,
        repo.url,
        type,
      ));
      await updateRepoExtensionCount(repo, type, extensions.length);
      return extensions;
    } catch (e) {
      Logger.log('Legado repo fetch failed ${repo.url}: $e');
      return const [];
    }
  }

  static List<Source> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) {
    final (body, repoUrl, itemType) = args;
    if (itemType != ItemType.novel) return const [];
    try {
      final decoded = jsonDecode(body);
      Iterable<dynamic> raw;
      if (decoded is List) {
        raw = decoded;
      } else if (decoded is Map && decoded['sources'] is List) {
        raw = decoded['sources'] as List;
      } else if (decoded is Map && decoded['data'] is List) {
        raw = decoded['data'] as List;
      } else if (decoded is Map && decoded['bookSourceList'] is List) {
        raw = decoded['bookSourceList'] as List;
      } else if (decoded is Map) {
        raw = [decoded];
      } else {
        return const [];
      }

      final seen = <String>{};
      final out = <Source>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final s = LegadoSource.fromLegadoJson(
          Map<String, dynamic>.from(item),
          repoUrl: repoUrl,
        );
        if ((s.bookSourceUrl ?? '').isEmpty) continue;
        if (s.id != null && !seen.add(s.id!)) continue;
        out.add(s);
      }
      return out;
    } catch (e) {
      debugPrint('Failed to parse Legado repo $repoUrl: $e');
      return const [];
    }
  }

  // --- install / uninstall / update ----------------------------------

  @override
  Stream<double> installSource(Source source) {
    // No download here - Legado sources are stored JSON, not a binary.
    return progressStream((_) async {
      try {
        const type = ItemType.novel;
        final s = source is LegadoSource
            ? source
            : LegadoSource.fromJson(source.toJson());

        final list = _loadInstalled(type)..removeWhere((e) => e.id == s.id);
        list.add(s);
        _saveInstalled(list, type);
        state(type).installed.value = List.unmodifiable(list);

        final avail = state(type).available;
        avail.value = avail.value.where((e) => e.id != s.id).toList();
        detectUpdates(state(type).rawAvailable.value, type);
      } catch (e) {
        Logger.log('Failed to install Legado source ${source.id}: $e');
        rethrow;
      }
    });
  }

  @override
  Future<void> uninstallSource(Source source) async {
    try {
      const type = ItemType.novel;
      final list = _loadInstalled(type)..removeWhere((e) => e.id == source.id);
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
      Logger.log('Failed to uninstall Legado source ${source.id}: $e');
    }
  }

  @override
  Stream<double> updateSource(Source source) {
    return progressStream((_) async {
      const type = ItemType.novel;
      final remote = state(type).rawAvailable.value.firstWhere(
        (e) => e.id == source.id,
        orElse: () => source,
      );
      final fresh = remote is LegadoSource
          ? remote
          : LegadoSource.fromJson(remote.toJson());

      final list = _loadInstalled(type);
      final i = list.indexWhere((e) => e.id == source.id);
      if (i == -1) return;
      fresh.hasUpdate = false;
      list[i] = fresh;
      _saveInstalled(list, type);
      state(type).installed.value = List.unmodifiable(list);
    });
  }

  @override
  void detectUpdates(List<Source> available, ItemType type) {
    if (type != ItemType.novel) return;
    final installed = _loadInstalled(type);
    if (installed.isEmpty || available.isEmpty) return;

    final repoMap = {for (final s in available) s.id: s};
    var changed = false;

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id];
      if (repo == null) continue;

      if (compareVersions(repo.version ?? '0', inst.version ?? '0') > 0) {
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
      _saveInstalled(installed, type);
      state(type).installed.value = List.unmodifiable(installed);
    }
  }

  // --- persistence -------------------------------------------------

  List<LegadoSource> _loadInstalled(ItemType type) {
    final encoded = getVal<List<String>>('$id-Installed-${type.name}');
    if (encoded == null || encoded.isEmpty) return [];
    final list = <LegadoSource>[];
    for (final e in encoded) {
      try {
        list.add(LegadoSource.fromJson(jsonDecode(e)));
      } catch (_) {}
    }
    return list;
  }

  void _saveInstalled(List<LegadoSource> list, ItemType type) {
    setVal(
      '$id-Installed-${type.name}',
      list.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }

  // --- deep links ------------------------------------------------

  @override
  Set<String> get schemes => {'legado', 'yuedu'};

  @override
  void handleSchemes(Uri uri) {
    final url =
        uri.queryParameters['src'] ??
        uri.queryParameters['url'] ??
        uri.queryParameters['data'];
    if (url != null && url.isNotEmpty) {
      addRepo(url, ItemType.novel);
    }
  }
}
