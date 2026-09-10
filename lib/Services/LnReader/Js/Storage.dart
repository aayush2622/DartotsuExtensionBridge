import 'dart:convert';

import 'package:flutter_qjs/flutter_qjs.dart';

import '../../../Settings/KvStore.dart';

/// `@libs/storage` bridge for LNReader plugins.
///
/// Upstream exposes a persistent KV store (`storage.get/set/delete/clearAll/
/// getAllKeys`) plus read-only `localStorage` / `sessionStorage`. This backs
/// `storage` with the plugin's [KvStore], namespaced per source so two plugins
/// can't clobber each other. The web-storage shims just return `null`.
class JsStorage {
  final JavascriptRuntime runtime;
  final String namespace;

  JsStorage(this.runtime, {required String sourceId})
    : namespace = 'lnreader-storage-$sourceId';

  Map<String, dynamic> _load() {
    final raw = getVal<String>(namespace);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  void _save(Map<String, dynamic> map) => setVal(namespace, jsonEncode(map));

  void init() {
    runtime.onMessage('storage_get', (dynamic args) {
      final key = args[0] as String;
      final raw = args.length > 1 && args[1] == true;
      final entry = _load()[key];
      if (entry == null) return null;
      if (raw) return entry;
      return (entry is Map && entry.containsKey('value'))
          ? entry['value']
          : entry;
    });

    runtime.onMessage('storage_set', (dynamic args) {
      final key = args[0] as String;
      final value = args[1];
      final expires = args.length > 2 ? args[2] : null;
      final map = _load();
      map[key] = {
        'created': DateTime.now().millisecondsSinceEpoch,
        'value': value,
        'expires': expires,
      };
      _save(map);
      return null;
    });

    runtime.onMessage('storage_delete', (dynamic args) {
      final map = _load()..remove(args[0] as String);
      _save(map);
      return null;
    });

    runtime.onMessage('storage_clear', (dynamic _) {
      _save({});
      return null;
    });

    runtime.onMessage('storage_keys', (dynamic _) {
      return jsonEncode(_load().keys.toList());
    });

    runtime.evaluate(r'''
const storage = {
  get(key, raw) {
    return sendMessage("storage_get", JSON.stringify([key, raw === true]));
  },
  set(key, value, expires) {
    let exp = null;
    if (expires instanceof Date) exp = expires.getTime();
    else if (typeof expires === "number") exp = expires;
    return sendMessage("storage_set", JSON.stringify([key, value, exp]));
  },
  delete(key) {
    return sendMessage("storage_delete", JSON.stringify([key]));
  },
  clearAll() {
    return sendMessage("storage_clear", JSON.stringify([]));
  },
  getAllKeys() {
    return JSON.parse(sendMessage("storage_keys", JSON.stringify([])));
  },
};

const localStorage = { get: () => null, getItem: () => null };
const sessionStorage = { get: () => null, getItem: () => null };
''');
  }
}
