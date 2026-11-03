import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../Models/Source.dart';
import 'Models/Source.dart';

/// Parses a Shosetsu repo's `index.json` into [SsSource]s.
///
/// The index is `{authors, libraries, scripts, styles, js}`; only `scripts`
/// entries with `type == "LuaScript"` (the only type this bridge's Lua
/// engine runs) become sources. Each entry is
/// `{id, name, fileName, imageURL, lang, ver, libVer, md5, type}` - the
/// script body lives at `<repoRoot>src/<lang>/<fileName>.lua`. Safe to run
/// inside `compute()` - no I/O, no state.
List<Source> parseShosetsuRepoIndex((String body, String repoRoot) args) {
  final (body, repoRoot) = args;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const [];

    final scripts = decoded['scripts'];
    if (scripts is! List) return const [];

    final root = repoRoot.endsWith('/') ? repoRoot : '$repoRoot/';
    final sources = <Source>[];

    for (final raw in scripts) {
      if (raw is! Map) continue;
      final e = raw.cast<String, dynamic>();

      if ((e['type'] as String?) != null && e['type'] != 'LuaScript') continue;

      final fileName = e['fileName']?.toString();
      final lang = e['lang']?.toString();
      if (fileName == null ||
          fileName.isEmpty ||
          lang == null ||
          lang.isEmpty) {
        continue;
      }

      sources.add(
        SsSource(
          id: e['id']?.toString(),
          name: e['name']?.toString(),
          lang: lang,
          version: e['ver']?.toString() ?? '1.0.0',
          versionLast: e['ver']?.toString() ?? '1.0.0',
          iconUrl: e['imageURL']?.toString(),
          itemType: ItemType.novel,
          repo: root,
          fileName: fileName,
          sourceCodeUrl: '${root}src/$lang/$fileName.lua',
        ),
      );
    }

    return sources;
  } catch (e) {
    debugPrint('Failed to parse Shosetsu repo index from $repoRoot: $e');
    return const [];
  }
}
