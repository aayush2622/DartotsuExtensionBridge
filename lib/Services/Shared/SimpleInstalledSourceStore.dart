import 'dart:convert';

import '../../Extensions/Extensions.dart';
import '../../Models/Source.dart';
import '../../Settings/KvStore.dart';

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
      } catch (_) {}
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
