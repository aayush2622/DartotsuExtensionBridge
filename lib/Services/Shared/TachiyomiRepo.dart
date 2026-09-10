import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../Extensions/Extensions.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import 'PackagedSource.dart';
import 'ProtoReader.dart';

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
  // Already an index endpoint (JSON or protobuf) — leave it alone.
  if (repoUrl.endsWith('index.min.json') || repoUrl.endsWith('.pb')) {
    return repoUrl;
  }
  final trimmed = repoUrl.replaceAll(RegExp(r'/+$'), '');
  return '$trimmed/index.min.json';
}

/// Rewrites a GitHub raw repo URL to a jsDelivr mirror, used as a fallback when
/// the primary host is unreachable. Returns `null` when the URL doesn't look
/// like `.../<owner>/<repo>[/<branch>]...`.
///
/// Handles both GitHub raw shapes and keeps whatever file the URL pointed at, so
/// an `index.pb` endpoint doesn't silently fall back to `index.min.json`:
///
/// * `raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>`
/// * `github.com/<owner>/<repo>/raw/<branch>/<path>`
String? tachiyomiFallbackRepoUrl(String repoUrl) {
  try {
    final stripped = repoUrl
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '');

    final parts = stripped.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length < 3) return null;

    final owner = parts[1];
    final repo = parts[2];

    // github.com puts a literal `raw` segment before the branch.
    final branchIndex = (parts.length > 3 && parts[3] == 'raw') ? 4 : 3;
    final branch = parts.length > branchIndex ? parts[branchIndex] : 'main';
    final path = parts.skip(branchIndex + 1).join('/');

    final base = 'https://gcore.jsdelivr.net/gh/$owner/$repo@$branch';
    return path.isEmpty ? base : '$base/$path';
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

  /// Direct download URL when the repo states one (the `index.pb` format does).
  /// `null` for the JSON format, where it is derived from [iconUrl] + [apkName].
  final String? apkUrl;

  /// Desktop JAR URL, when the repo publishes one alongside the APK.
  final String? jarUrl;

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
    this.apkUrl,
    this.jarUrl,
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
    // Runs inside compute(): DartotsuExtensionBridge.context isn't available in
    // the worker isolate, so log via debugPrint rather than Logger.
    debugPrint('Failed to parse Tachiyomi repo index from $repoUrl: $e');
    return const [];
  }
}

/// Flags installed [PackagedSource]s that have a newer version in [available],
/// copying the fresh `apkName` / `iconUrl` / `version` across and bumping the
/// [Extension]'s installed list so listeners refresh.
///
/// Shared by every Tachiyomi-style backend; the per-class `detectUpdates`
/// override is now a one-line delegate to this.
void detectTachiyomiUpdates(
  Extension ext,
  List<Source> available,
  ItemType type,
) {
  final repoById = <String?, PackagedSource>{
    for (final s in available)
      if (s is PackagedSource) s.id: s,
  };

  final installed = ext.state(type).installed.value;
  var changed = false;

  for (final inst in installed) {
    if (inst is! PackagedSource) continue;

    final repo = repoById[inst.id];
    if (repo == null) continue;

    if (ext.compareVersions(repo.version ?? '0', inst.version ?? '0') > 0) {
      inst
        ..hasUpdate = true
        ..apkName = repo.apkName
        ..iconUrl = repo.iconUrl
        ..versionLast = repo.version;
      changed = true;
    }
  }

  if (changed) {
    ext.state(type).installed.value = List.unmodifiable(installed);
  }
}

// ---------------------------------------------------------------------------
// index.pb (protobuf) repositories
// ---------------------------------------------------------------------------

/// Wire format of a repository index.
enum RepoIndexFormat {
  /// The historical `index.min.json` array.
  json,

  /// The gzipped-protobuf `index.pb` introduced by Mihon / keiyoushi.
  protobuf,
}

/// Picks the index format from the URL. Anything ending in `.pb` is protobuf;
/// everything else keeps the legacy JSON behaviour.
RepoIndexFormat tachiyomiIndexFormat(String url) =>
    url.endsWith('.pb') ? RepoIndexFormat.protobuf : RepoIndexFormat.json;

/// `contentWarning` enum from the index.pb schema.
/// 0 unspecified, 1 safe, 2 mixed, 3 nsfw — Mihon treats `>= mixed` as NSFW.
const _pbContentWarningMixed = 2;

// Field numbers, mirroring mihon's NetworkExtensionStore.
const _pbStoreExtensionList = 101;
const _pbStoreExtensionListUrl = 102;
const _pbListExtensions = 1;
const _pbExtName = 1;
const _pbExtPackageName = 2;
const _pbExtResources = 3;
const _pbExtLib = 4;
const _pbExtVersionCode = 5;
const _pbExtVersionName = 6;
const _pbExtContentWarning = 7;
const _pbExtSources = 8;
const _pbResApkUrl = 1;
const _pbResIconUrl = 2;
const _pbResJarUrl = 501; // keiyoushi extension: prebuilt desktop jar
const _pbSourceId = 1;
const _pbSourceLanguage = 3;

Uint8List _gunzipIfNeeded(Uint8List body) {
  if (body.length >= 2 && body[0] == 0x1f && body[1] == 0x8b) {
    return Uint8List.fromList(gzip.decode(body));
  }
  return body;
}

/// Some stores ship only metadata at `index.pb` and point at a second URL for
/// the extension list itself. Returns that URL, or `null` when the list is
/// inlined (the common case).
String? tachiyomiPbExtensionListUrl(Uint8List body) {
  try {
    final store = ProtoMessage.decode(_gunzipIfNeeded(body));
    if (store.has(_pbStoreExtensionList)) return null;
    return store.readString(_pbStoreExtensionListUrl);
  } catch (_) {
    return null;
  }
}

/// Parses a gzipped-protobuf `index.pb` [body] into concrete sources.
///
/// Unlike the JSON format there are no `"Aniyomi: "` / `"Tachiyomi: "` name
/// prefixes, so the item type comes from the package name
/// (`eu.kanade.tachiyomi.animeextension.*` vs `...extension.*`), falling back to
/// [targetType] when it can't be told apart.
///
/// Safe to call inside `compute()`.
List<T> parseTachiyomiPbIndex<T extends Source>({
  required Uint8List body,
  required String repoUrl,
  required ItemType targetType,
  required T Function(TachiyomiRepoEntry entry) factory,
}) {
  try {
    final store = ProtoMessage.decode(_gunzipIfNeeded(body));

    final list = store.readMessage(_pbStoreExtensionList);
    if (list == null) return const [];

    final sources = <T>[];

    for (final ext in list.readMessages(_pbListExtensions)) {
      final pkgName = ext.readString(_pbExtPackageName);
      final itemType = _pbItemType(pkgName) ?? targetType;
      if (itemType != targetType) continue;

      final resources = ext.readMessage(_pbExtResources);
      final apkUrl = resources?.readString(_pbResApkUrl);
      final iconUrl = resources?.readString(_pbResIconUrl) ?? '';
      final jarUrl = resources?.readString(_pbResJarUrl);

      final entrySources = ext.readMessages(_pbExtSources);
      final id = entrySources.isEmpty
          ? ''
          : (entrySources.first.readInt(_pbSourceId)?.toString() ?? '');

      final languages = <String>{
        for (final s in entrySources)
          if (s.readString(_pbSourceLanguage) case final l? when l.isNotEmpty)
            l,
      };

      final warning = ext.readInt(_pbExtContentWarning) ?? 0;

      sources.add(
        factory(
          TachiyomiRepoEntry(
            id: id,
            name: ext.readString(_pbExtName) ?? '',
            pkgName: pkgName,
            apkName: apkUrl?.split('/').last,
            lang: languages.length == 1 ? languages.first : 'all',
            version:
                ext.readString(_pbExtVersionName) ??
                ext.readInt(_pbExtVersionCode)?.toString(),
            isNsfw: warning >= _pbContentWarningMixed,
            itemType: itemType,
            repo: repoUrl,
            iconUrl: iconUrl,
            apkUrl: apkUrl,
            jarUrl: jarUrl,
          ),
        ),
      );
    }

    return List.unmodifiable(sources);
  } catch (e) {
    debugPrint('Failed to parse index.pb from $repoUrl: $e');
    return const [];
  }
}

ItemType? _pbItemType(String? pkgName) {
  if (pkgName == null) return null;
  if (pkgName.contains('.animeextension.')) return ItemType.anime;
  if (pkgName.contains('.extension.')) return ItemType.manga;
  return null;
}

/// Reads `extensionLib` (field 4) — unused by the bridge today but kept next to
/// the other field constants so the schema stays documented in one place.
String? tachiyomiPbExtensionLib(ProtoMessage extension) =>
    extension.readString(_pbExtLib);

/// Result of a repo index fetch: the raw bytes plus the URL they came from
/// (which may be the jsDelivr mirror rather than the URL originally asked for).
typedef RepoIndexResponse = ({Uint8List body, String url});

/// Fetches a repository index, trying [repoUrl] first and falling back to the
/// jsDelivr mirror when the primary host fails.
///
/// Works for both `index.min.json` and `index.pb` — the bytes are returned
/// undecoded so the caller can dispatch on [tachiyomiIndexFormat]. Throws when
/// both the primary and the fallback fail.
///
/// This replaces the primary/fallback block that each backend used to inline
/// twice (once in `addRepo`, once in `fetchRepo`).
Future<RepoIndexResponse> fetchTachiyomiRepoIndex(
  http.Client client,
  String repoUrl, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final primary = tachiyomiIndexUrl(repoUrl);

  try {
    final res = await client.get(Uri.parse(primary)).timeout(timeout);
    if (res.statusCode == 200) return (body: res.bodyBytes, url: primary);
    throw Exception('Primary index fetch failed (${res.statusCode})');
  } catch (e) {
    Logger.log('Primary repo failed: $primary → $e');

    final fallback = tachiyomiFallbackRepoUrl(repoUrl);
    if (fallback == null) {
      throw Exception('Failed to fetch repo and no fallback available');
    }

    final fallbackUrl = tachiyomiIndexUrl(fallback);

    try {
      final res = await client.get(Uri.parse(fallbackUrl)).timeout(timeout);
      if (res.statusCode == 200) return (body: res.bodyBytes, url: fallbackUrl);
      throw Exception('Fallback index fetch failed (${res.statusCode})');
    } catch (e2) {
      Logger.log('Fallback failed: $fallbackUrl → $e2');
      throw Exception('Failed to fetch repo (primary + fallback)');
    }
  }
}
