import 'dart:convert';

import '../../Extensions/Extensions.dart';
import '../../Models/Source.dart';
import '../../Settings/KvStore.dart';

/// KV-backed persistence for the "simple" backends that store an installed
/// source's whole JSON blob directly (Mangayomi, Sora, LnReader, Legado) -
/// unlike the Tachiyomi-style / Kotatsu backends, there's no native side to
/// re-scan, so the installed list itself is the source of truth and is
/// round-tripped through `getVal`/`setVal`.
///
/// Every one of them had its own byte-identical `_loadInstalled`/
/// `_saveInstalled` pair (same `'$id-Installed-${type.name}'` key shape),
/// bar Mangayomi's not tolerating a malformed stored entry - unifying on the
/// skip-and-keep-going behavior here is strictly safer, not just less code.
mixin SimpleInstalledSourceStore<T extends Source> on Extension {
  T Function(Map<String, dynamic>) get sourceFromJson;

  String _installedKey(ItemType type) => '$id-Installed-${type.name}';

  List<T> loadInstalled(ItemType type) {
    final encoded = getVal<List<String>>(_installedKey(type));
    if (encoded == null || encoded.isEmpty) return [];

    final list = <T>[];
    for (final e in encoded) {
      try {
        list.add(sourceFromJson(jsonDecode(e)));
      } catch (_) {
        // Drop a single corrupted entry rather than losing the whole list.
      }
    }
    return list;
  }

  void saveInstalled(List<T> list, ItemType type) {
    setVal(
      _installedKey(type),
      list.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }
}
