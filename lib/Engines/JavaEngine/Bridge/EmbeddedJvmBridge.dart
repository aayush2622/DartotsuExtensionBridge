import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../Logger.dart';
import 'JniBridge.dart' show JavaBridge, emptyJavaBridgeValue;

/// iOS implementation of [JavaBridge].
///
/// Desktop platforms run each backend JAR as a `java -jar` subprocess
/// ([SidecarBridge]); iOS cannot spawn processes and forbids JIT, so instead a
/// single interpreter-only OpenJDK Zero VM is embedded in-process (see
/// `ios/dartotsu_extension_bridge/Sources/dartotsu_extension_bridge/EmbeddedJvm.mm`,
/// modelled on
/// <https://github.com/kodjodevf/m_extension_server>). That VM boots once with
/// only a small shim JAR (`mextension/EmbeddedBridge`) on its classpath; each
/// backend's fat JAR is then attached in its own child-first class loader and
/// driven reflectively through the same request shape the sidecar speaks
/// (`{method, args}` in, `{success, data|error}` out).
///
/// Everything crosses a single method channel:
/// * `start`  – create the VM (idempotent; safe to call from every backend).
/// * `load`   – attach `{jarPath}` in a child-first loader, instantiate its
///              `Main.api()`, cache it keyed by `jarPath`.
/// * `call`   – `{jarPath, request}` → response JSON envelope.
/// * `unload` – drop `{jarPath}`'s loader + api (the VM itself stays up).
class EmbeddedJvmBridge implements JavaBridge {
  static const _channel = MethodChannel(
    'dartotsu_extension_bridge/embedded_jvm',
  );

  /// One VM per process — starting it is guarded so the four desktop backends
  /// racing through [init] at boot only pay for it once.
  static Future<void>? _vmStart;

  String? _jarPath;
  bool _loaded = false;

  @override
  Future<void> init({required String pluginJarPath}) async {
    if (_loaded) return;
    _jarPath = pluginJarPath;

    await (_vmStart ??= _channel.invokeMethod<void>('start').catchError((
      Object e,
    ) {
      _vmStart = null; // let a later backend retry a failed VM boot
      throw e;
    }));

    await _channel.invokeMethod<void>('load', {'jarPath': pluginJarPath});
    _loaded = true;
    Logger.log('Embedded JVM: loaded $pluginJarPath');
  }

  @override
  Future<T> call<T>(
    String method, [
    Map<String, dynamic>? args,
    bool throwError = false,
  ]) async {
    if (!_loaded || _jarPath == null) {
      throw Exception('Embedded JVM bridge not initialized');
    }

    try {
      final envelope = await _channel.invokeMethod<String>('call', {
        'jarPath': _jarPath,
        'request': jsonEncode({'method': method, 'args': args ?? {}}),
      });

      final decodedEnvelope =
          jsonDecode(envelope ?? '{}') as Map<String, dynamic>;

      if (decodedEnvelope['success'] != true) {
        throw Exception(
          decodedEnvelope['error']?.toString() ?? 'Embedded JVM call failed',
        );
      }

      final data = decodedEnvelope['data'];
      final decoded = data is String
          ? _toDart(jsonDecode(data))
          : _toDart(data);

      if (decoded is List && decoded.every((e) => e is Map<String, dynamic>)) {
        return List<Map<String, dynamic>>.from(decoded) as T;
      }
      if (decoded is Map<String, dynamic>) {
        return decoded as T;
      }
      return decoded as T;
    } catch (e, s) {
      Logger.log('[EMBEDDED-JVM] Call failed: $e\n$s', show: true);
      if (throwError) rethrow;
      return emptyJavaBridgeValue<T>();
    }
  }

  @override
  void dispose() {
    _loaded = false;
    final jar = _jarPath;
    _jarPath = null;
    if (jar == null) return;
    unawaited(
      _channel
          .invokeMethod<void>('unload', {'jarPath': jar})
          .catchError((_) {}),
    );
  }

  dynamic _toDart(dynamic value) {
    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((k, v) => result[k.toString()] = _toDart(v));
      return result;
    }
    if (value is List) return value.map(_toDart).toList();
    return value;
  }
}
