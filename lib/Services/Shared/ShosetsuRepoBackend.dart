import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../Extensions/Extensions.dart';
import '../../Extensions/RepoGuard.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../Shosetsu/Manifest.dart';
import '../Shosetsu/Models/Source.dart';
import 'SimpleInstalledSourceStore.dart';

/// Shared `addRepo`/`fetchRepo`/install-uninstall for the Shosetsu backend,
/// used by both the Android and desktop [Extension]s since neither needs
/// anything platform-specific here - a script is a plain text file, not an
/// APK/jar that needs a system install step.
///
/// Each installed script is written as `<id>.lua` plus a `<id>.lua.meta.json`
/// sidecar (`{"repo": <repo root>, "lang": <lang>}`) the native side reads to
/// resolve `Require()` against the right repository and to report `lang` in
/// `getInstalledNovelExtensions` (a script's own metadata header has no
/// language field - only the repo index does).
mixin ShosetsuRepoBackend on Extension, SimpleInstalledSourceStore<SsSource> {
  http.Client get repoClient;

  Future<Directory?> get extensionsDir;

  @override
  Set<RepoFormat> get repoFormats => const {RepoFormat.shosetsu};

  @override
  Stream<double> addRepo(String repoUrl, ItemType type) =>
      addRepoTask(repoUrl, type, (url, _) async {
        final root = url.endsWith('/') ? url : '$url/';
        final bytes = await downloadRepoIndex(
          repoClient,
          '${root}index.json',
          timeout: const Duration(seconds: 15),
        );
        final body = utf8.decode(bytes, allowMalformed: true);
        final sources = await compute(parseShosetsuRepoIndex, (body, root));
        if (sources.isEmpty) throw invalidRepo(type, body: bytes, url: url);
        await commitRepo(
          Repo(
            url: root,
            name: repoNameFromUrl(root),
            extensions: sources.length.toString(),
          ),
          type,
          sources: sources,
        );
      });

  @override
  Future<List<Source>> fetchRepo(Repo repo, ItemType type) async {
    try {
      final root = repo.url.endsWith('/') ? repo.url : '${repo.url}/';
      final bytes = await downloadRepoIndex(
        repoClient,
        '${root}index.json',
        timeout: const Duration(seconds: 15),
      );
      final sources = await compute(
        parseShosetsuRepoIndex,
        (utf8.decode(bytes, allowMalformed: true), root),
      );
      await updateRepoExtensionCount(repo, type, sources.length);
      return sources;
    } catch (e) {
      Logger.log('Failed to fetch $name repo ${repo.url}: $e');
      return const [];
    }
  }

  File _scriptFile(Directory dir, String id) => File(p.join(dir.path, '$id.lua'));

  File _metaFile(Directory dir, String id) =>
      File(p.join(dir.path, '$id.lua.meta.json'));

  @override
  Stream<double> installSource(Source source) {
    return progressStream((report) async {
      final s = source as SsSource;
      final type = s.itemType!;
      final id = s.id!;

      final url = s.sourceCodeUrl;
      if (url == null || url.isEmpty) throw Exception('Missing script URL');

      final res = await repoClient.get(Uri.parse(url));
      if (res.statusCode != 200) {
        throw Exception('Script download failed (${res.statusCode})');
      }
      s.sourceCode = res.body;

      final dir = await extensionsDir;
      await dir!.create(recursive: true);
      await _scriptFile(dir, id).writeAsString(res.body);
      await _metaFile(
        dir,
        id,
      ).writeAsString(jsonEncode({'repo': s.repo, 'lang': s.lang}));

      final list = loadInstalled(type)..removeWhere((e) => e.id == id);
      list.add(s);
      saveInstalled(list, type);
      state(type).installed.value = List.unmodifiable(list);

      final avail = state(type).available;
      avail.value = avail.value.where((e) => e.id != id).toList();
      detectUpdates(state(type).rawAvailable.value, type);
    });
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as SsSource;
    final type = s.itemType!;
    final id = s.id!;

    try {
      final dir = await extensionsDir;
      if (dir != null) {
        final script = _scriptFile(dir, id);
        if (await script.exists()) await script.delete();
        final meta = _metaFile(dir, id);
        if (await meta.exists()) await meta.delete();
      }

      final list = loadInstalled(type)..removeWhere((e) => e.id == id);
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
      Logger.log('Uninstall failed $id: $e');
    }
  }

  @override
  Stream<double> updateSource(Source source) => installSource(source);

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

      if (compareVersions(repo.version ?? '0', inst.version ?? '0') > 0) {
        installed[i] = inst
          ..hasUpdate = true
          ..versionLast = repo.version
          ..sourceCodeUrl = (repo as SsSource).sourceCodeUrl;
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
}
