import 'dart:convert';

import '../../Logger.dart';
import '../../Models/Source.dart';

/// Helpers shared by every backend that consumes a Tachiyomi-style
/// `index.min.json` repository (Aniyomi, IReader, Tsundoku — both the Android
/// and desktop variants).
///
/// Previously each of those `*Extensions` classes carried its own byte-for-byte
/// copy of `fallbackRepoUrl` and a near-identical `_parseExtensions`; the only
/// real differences were the concrete `Source` subtype and the display-name
/// prefix. Those live here now.

/// Normalises `repoUrl` to its `index.min.json` endpoint, tolerating a trailing
/// slash or an URL that already points at the index.
String tachiyomiIndexUrl(String repoUrl) {
  if (repoUrl.endsWith('index.min.json')) return repoUrl;
  final trimmed = repoUrl.replaceAll(RegExp(r'/+$'), '');
  return '$trimmed/index.min.json';
}

/// Rewrites a GitHub raw repo URL to a jsDelivr mirror, used as a fallback when
/// the primary host is unreachable. Returns `null` when the URL doesn't look
/// like `.../<owner>/<repo>[/<branch>]...`.
String? tachiyomiFallbackRepoUrl(String repoUrl) {
  try {
    final stripped = repoUrl
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '')
        .replaceAll('/index.min.json', '');

    final parts = stripped.split('/');
    if (parts.length < 3) return null;

    final owner = parts[1];
    final repo = parts[2];
    final branch = parts.length > 3 ? parts[3] : 'main';

    return 'https://gcore.jsdelivr.net/gh/$owner/$repo@$branch';
  } catch (_) {
    return null;
  }
}

/// One extension package as described by an `index.min.json` entry, already
/// resolved against the repo URL. Field names mirror the `Source` constructor
/// so a backend's factory is a straight field copy.
class TachiyomiRepoEntry {
  final String id;
  final String name;
  final String? pkgName;
  final String? apkName;
  final String? lang;
  final String? version;
  final bool isNsfw;
  final ItemType itemType;
  final String repo;
  final String iconUrl;

  const TachiyomiRepoEntry({
    required this.id,
    required this.name,
    required this.pkgName,
    required this.apkName,
    required this.lang,
    required this.version,
    required this.isNsfw,
    required this.itemType,
    required this.repo,
    required this.iconUrl,
  });
}

/// Parses a Tachiyomi `index.min.json` [body] into concrete sources.
///
/// [prefixes] maps a display-name prefix (e.g. `'Aniyomi: '`) to the
/// [ItemType] it denotes; entries whose resolved type isn't [targetType] are
/// skipped. The prefix is stripped from the name using its own length, so
/// callers no longer have to hand-count offsets. [factory] turns a resolved
/// [TachiyomiRepoEntry] into the backend's `Source` subtype.
///
/// Safe to call inside `compute()` — it performs no I/O and touches no state.
List<T> parseTachiyomiRepoIndex<T extends Source>({
  required String body,
  required String repoUrl,
  required ItemType targetType,
  required Map<String, ItemType> prefixes,
  required T Function(TachiyomiRepoEntry entry) factory,
}) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];

    const suffix = '/index.min.json';
    final baseIconUrl = repoUrl.endsWith(suffix)
        ? repoUrl.substring(0, repoUrl.length - suffix.length)
        : repoUrl;

    final sources = <T>[];

    for (final item in decoded) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final name = map['name'] as String? ?? '';

      ItemType? detectedType;
      String displayName = name;
      for (final entry in prefixes.entries) {
        if (name.startsWith(entry.key)) {
          detectedType = entry.value;
          displayName = name.substring(entry.key.length);
          break;
        }
      }

      if (detectedType != targetType) continue;

      final sourcesList = map['sources'];
      final id = (sourcesList is List && sourcesList.isNotEmpty)
          ? (sourcesList.first['id']?.toString() ?? '')
          : '';

      sources.add(
        factory(
          TachiyomiRepoEntry(
            id: id,
            name: displayName,
            pkgName: map['pkg'] as String?,
            apkName: map['apk'] as String?,
            lang: map['lang'] as String?,
            version: map['version']?.toString(),
            isNsfw: map['nsfw'] == 1,
            itemType: detectedType!,
            repo: repoUrl,
            iconUrl: '$baseIconUrl/icon/${map['pkg']}.png',
          ),
        ),
      );
    }

    return List.unmodifiable(sources);
  } catch (e) {
    Logger.log('Failed to parse Tachiyomi repo index from $repoUrl: $e');
    return const [];
  }
}
