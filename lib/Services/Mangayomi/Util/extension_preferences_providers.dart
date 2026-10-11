import 'dart:convert';

import '../../../Settings/KvStore.dart';
import '../Eval/dart/model/source_preference.dart';
import '../Models/Source.dart';
import 'get_source_preference.dart';
import 'string_extensions.dart';

abstract interface class PrefKv {
  T? get<T>(String key);
  void set(String key, dynamic value);
}

class _KvStorePrefKv implements PrefKv {
  const _KvStorePrefKv();

  @override
  T? get<T>(String key) => getVal<T>(key);

  @override
  void set(String key, dynamic value) => setVal(key, value);
}

/// Where source preferences are read and written. Worker isolates replace this
/// with a snapshot-backed store, since the host's database isn't reachable from
/// there.
PrefKv prefKv = const _KvStorePrefKv();

/// Sources already loaded in this isolate, so a preference lookup doesn't have
/// to decode every installed source out of storage to find one.
final Map<String, MSource> knownSources = {};

List<SourcePreference> _loadPrefs(String sourceId) {
  final encoded = prefKv.get<List<String>>("sourcePrefs_$sourceId");

  if (encoded == null || encoded.isEmpty) return [];

  final list = <SourcePreference>[];

  for (final e in encoded) {
    try {
      list.add(SourcePreference.fromJson(jsonDecode(e)));
    } catch (_) {}
  }

  return list;
}

void _savePrefs(String sourceId, List<SourcePreference> prefs) {
  prefKv.set(
    "sourcePrefs_$sourceId",
    prefs.map((e) => jsonEncode(e.toJson())).toList(growable: false),
  );
}

void setPreferenceSetting(SourcePreference sourcePreference, MSource source) {
  var id = extractSourceId(source.id!).toString();
  final prefs = _loadPrefs(id);

  final index = prefs.indexWhere((e) => e.key == sourcePreference.key);

  if (index >= 0) {
    prefs[index] = sourcePreference;
  } else {
    prefs.add(sourcePreference);
  }

  _savePrefs(id, prefs);
}

dynamic getPreferenceValue(String sourceId, String key) {
  final pref = getSourcePreferenceEntry(key, sourceId);

  if (pref.listPreference != null) {
    final p = pref.listPreference!;
    return p.entryValues![p.valueIndex!];
  } else if (pref.checkBoxPreference != null) {
    return pref.checkBoxPreference!.value;
  } else if (pref.switchPreferenceCompat != null) {
    return pref.switchPreferenceCompat!.value;
  } else if (pref.editTextPreference != null) {
    return pref.editTextPreference!.value;
  }

  return pref.multiSelectListPreference!.values;
}

SourcePreference getSourcePreferenceEntry(String key, String sourceId) {
  var id = extractSourceId(sourceId).toString();
  final prefs = _loadPrefs(id);

  final pref = prefs.where((e) => e.key == key).firstOrNull;

  if (pref != null) return pref;

  final source = getInstalledSource(sourceId);

  final defaultPref = getSourcePreference(source: source).firstWhere(
    (e) => e.key == key,
    orElse: () => throw "Error when getting source preference",
  );

  setPreferenceSetting(defaultPref, source);

  return defaultPref;
}

/// Applies the stored value (if any) over a source's default preference.
SourcePreference resolveSourcePreference(
  SourcePreference defaultPref,
  MSource source,
) {
  final id = extractSourceId(source.id!).toString();
  final stored = _loadPrefs(id).where((e) => e.key == defaultPref.key);
  if (stored.isNotEmpty) return stored.first;

  setPreferenceSetting(defaultPref, source);
  return defaultPref;
}

String getSourcePreferenceStringValue(
  String sourceId,
  String key,
  String defaultValue,
) {
  final kvKey = "sourcePrefString_${sourceId}_$key";

  final value = prefKv.get<String>(kvKey);

  if (value == null) {
    setSourcePreferenceStringValue(sourceId, key, defaultValue);
    return defaultValue;
  }

  return value;
}

void setSourcePreferenceStringValue(String sourceId, String key, String value) {
  final kvKey = "sourcePrefString_${sourceId}_$key";
  prefKv.set(kvKey, value);
}

int extractSourceId(String id) {
  final index = id.indexOf('@');
  if (index == -1) return id.toNullInt() ?? 0;
  return id.substring(0, index).toNullInt() ?? 0;
}

MSource getInstalledSource(String sourceId) {
  final known = knownSources[sourceId];
  if (known != null) return known;

  final anime = getVal<List<String>>('mangayomi-Installed-anime') ?? [];
  final manga = getVal<List<String>>('mangayomi-Installed-manga') ?? [];

  for (final list in [anime, manga]) {
    for (final e in list) {
      try {
        final source = MSource.fromJson(jsonDecode(e));
        if (source.id == sourceId) {
          return source;
        }
      } catch (_) {}
    }
  }

  throw Exception("Installed source not found: $sourceId");
}
