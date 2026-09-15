import 'dart:async';
import 'dart:convert';

import 'package:isar_community/isar.dart';

import '../Logger.dart';
import '../dartotsu_extension_bridge.dart';

part 'KvStore.g.dart';

@collection
class KvEntry {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String key;

  late String value;
}

class KvStore {
  static final Isar _isar = DartotsuExtensionBridge.context.isar;
  static final Map<String, dynamic> _pendingWrites = {};
  static Future<void> _writeQueue = Future.value();

  static final Map<String, dynamic> _cache = {};
  static const Object _notFound = Object();

  static Future<void> set(String key, dynamic value) {
    // Each call captures its own `value` in the closure below rather than
    // re-reading _pendingWrites[key] when the queued task actually runs -
    // otherwise a second set() to the same key overwrites the shared map
    // entry before the first queued task executes, and both tasks end up
    // persisting whatever happens to be in the map at that instant (the
    // first task can even end up persisting the *second* call's value, then
    // clearing the pending marker, causing the second task to persist a
    // just-cleared `null`). Capturing `value` here makes each task write
    // exactly what its own set() call was asked to write.
    _pendingWrites[key] = value;

    final completer = Completer<void>();

    // The shared _writeQueue chain must never itself become an error
    // future - `.then` without `onError` would skip every subsequent
    // queued task (for any key) once one write throws, permanently
    // wedging all future persistence. Failures are reported to this
    // call's own completer instead, keeping the chain alive.
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _isar.writeTxn(() async {
          final existing = await _isar.kvEntrys
              .filter()
              .keyEqualTo(key)
              .findFirst();

          final entry = existing ?? KvEntry();

          entry.key = key;
          entry.value = _encode(value);

          await _isar.kvEntrys.put(entry);
        });

        _cache[key] = value;

        if (identical(_pendingWrites[key], value)) {
          _pendingWrites.remove(key);
        }

        completer.complete();
      } catch (e, st) {
        if (identical(_pendingWrites[key], value)) {
          _pendingWrites.remove(key);
        }

        completer.completeError(e, st);
      }
    });

    return completer.future;
  }

  static T? get<T>(String key) {
    if (_pendingWrites.containsKey(key)) {
      final value = _pendingWrites[key];
      if (value == null) return null;
      if (value is T) return value;
    }

    if (_cache.containsKey(key)) {
      final cached = _cache[key];
      if (identical(cached, _notFound)) return null;
      return _cast<T>(key, cached);
    }

    final entry = _isar.kvEntrys.filter().keyEqualTo(key).findFirstSync();
    if (entry == null) {
      _cache[key] = _notFound;
      return null;
    }

    final decoded = _decode(entry.value);
    _cache[key] = decoded;

    return _cast<T>(key, decoded);
  }

  static T? _cast<T>(String key, dynamic decoded) {
    if (decoded == null) return null;

    if (decoded is T) return decoded;

    // Handle List<T>
    if (decoded is List) {
      if (T == List<String>) return List<String>.from(decoded) as T;
      if (T == List<int>) return List<int>.from(decoded) as T;
      if (T == List<double>) return List<double>.from(decoded) as T;
      if (T == List<bool>) return List<bool>.from(decoded) as T;
    }

    throw StateError(
      'Stored value for key "$key" is not of expected type $T '
      '(actual: ${decoded.runtimeType})',
    );
  }

  static Future<void> remove(String key) async {
    _cache.remove(key);
    _pendingWrites.remove(key);

    await _isar.writeTxn(() async {
      await _isar.kvEntrys.filter().keyEqualTo(key).deleteAll();
    });

    _cache[key] = _notFound;
  }

  static String _encode(dynamic value) => jsonEncode(_wrap(value));

  static dynamic _decode(String raw) {
    final data = jsonDecode(raw);
    return _unwrap(data);
  }

  static Map<String, dynamic> _wrap(dynamic value) {
    if (value == null) return {'t': 'null', 'v': null};
    if (value is String) return {'t': 'string', 'v': value};
    if (value is int) return {'t': 'int', 'v': value};
    if (value is double) return {'t': 'double', 'v': value};
    if (value is bool) return {'t': 'bool', 'v': value};

    if (value is List) {
      return {'t': 'list', 'v': value.map(_wrap).toList()};
    }

    throw UnsupportedError(
      'KvStore only supports primitive values and List<primitive>',
    );
  }

  static dynamic _unwrap(Map<String, dynamic> data) {
    final type = data['t'];
    final value = data['v'];

    switch (type) {
      case 'null':
        return null;
      case 'string':
      case 'int':
      case 'double':
      case 'bool':
        return value;
      case 'list':
        return (value as List)
            .map((e) => _unwrap(e as Map<String, dynamic>))
            .toList();
      default:
        throw StateError('Unknown stored type: $type');
    }
  }
}

T? getVal<T>(String key, {T? defaultValue}) {
  try {
    return KvStore.get<T>(key) ?? defaultValue;
  } catch (e) {
    Logger.log('Failed to get value for key "$key": $e');
    return defaultValue;
  }
}

void setVal(String key, dynamic value) {
  KvStore.set(key, value).catchError((Object e) {
    Logger.log('Failed to set value for key "$key": $e');
  });
}
