import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../Models/Source.dart';
import 'Models/Source.dart';

List<Source> parseAidokuManifest(String body, String repoUrl) {
  try {
    final decoded = jsonDecode(body);
    final list = decoded is List
        ? decoded
        : decoded is Map
        ? decoded['sources']
        : null;
    if (list is! List) return const [];

    final manifestUri = Uri.parse(repoUrl);
    final sources = <Source>[];

    for (final raw in list) {
      if (raw is! Map) continue;
      final e = raw.cast<String, dynamic>();

      final downloadPath = e['downloadURL']?.toString();
      if (downloadPath == null || downloadPath.isEmpty) continue;

      final version = (e['version'] ?? 0).toString();
      final iconPath = e['iconURL']?.toString();
      final languages =
          (e['languages'] as List?)?.map((v) => v.toString()).toList() ??
          const [];

      sources.add(
        AidokuSource(
          id: e['id']?.toString(),
          name: e['name']?.toString(),
          baseUrl: e['baseURL']?.toString(),
          lang: languages.isNotEmpty ? languages.first : null,
          version: version,
          versionLast: version,
          iconUrl: iconPath == null
              ? null
              : manifestUri.resolve(iconPath).toString(),
          itemType: ItemType.manga,
          repo: repoUrl,
          downloadUrl: manifestUri.resolve(downloadPath).toString(),
          languages: languages,
          contentRating: e['contentRating'] ?? 0,
          minAppVersion: e['minAppVersion']?.toString(),
        ),
      );
    }
    return sources;
  } catch (e) {
    debugPrint('Failed to parse Aidoku manifest from $repoUrl: $e');
    return const [];
  }
}
