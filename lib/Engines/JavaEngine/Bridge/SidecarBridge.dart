import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../Logger.dart';
import '../JavaInstaller.dart';
import 'JniBridge.dart';

class SidecarBridge implements JavaBridge {
  // Safety net for a response that will never arrive (e.g. the sidecar
  // died between the `_initialized` check and the write, or a response was
  // dropped) - without a bound, `call()` awaits its Completer forever and
  // leaks an entry in `_pending` for the lifetime of the process.
  static const _callTimeout = Duration(seconds: 120);

  Process? _process;

  StreamSubscription<String>? _stdoutSub;

  final _pending = <int, Completer<dynamic>>{};

  int _nextId = 0;

  bool _initialized = false;

  @override
  Future<void> init({required String pluginJarPath}) async {
    if (_initialized) return;

    Logger.log('Starting sidecar: $pluginJarPath');
    final javaPath = await JavaRuntimeManager.ensureInstalled();

    if (javaPath == null) throw Exception('Java runtime not found');

    _process = await Process.start(javaPath, [
      '-Dfile.encoding=UTF-8',
      '-Dsun.stdout.encoding=UTF-8',
      '-Dsun.stderr.encoding=UTF-8',
      '-Xms128m',
      '-Xmx512m',
      '-jar',
      pluginJarPath,
    ]);

    // The stdin sink can report write failures (e.g. broken pipe once the
    // sidecar process has died) through its `done` future instead of
    // throwing synchronously from `writeln`. Without a listener here that
    // surfaces as an uncaught zone error and can take down the host app.
    unawaited(_process!.stdin.done.catchError((_) {}));

    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);

    _process!.stderr.transform(utf8.decoder).listen((line) {
      Logger.log('[SIDECAR] $line');
    });

    unawaited(
      _process!.exitCode.then((code) {
        Logger.log('Sidecar exited with code $code');

        // Without this, every call() made after the sidecar dies still
        // passes the `_initialized` guard, writes to a dead stdin, and
        // waits out the full _callTimeout with no chance of a response -
        // this makes those calls fail immediately instead.
        _initialized = false;
        _process = null;

        for (final c in _pending.values) {
          if (!c.isCompleted) {
            c.completeError(Exception('Sidecar exited with code $code'));
          }
        }

        _pending.clear();
      }),
    );

    _initialized = true;

    Logger.log('Sidecar started');
  }

  void _handleLine(String line) {
    try {
      final json = jsonDecode(line);

      final id = json['id'];

      final completer = _pending.remove(id);

      if (completer == null) {
        Logger.log('[SIDECAR] No pending request');
        return;
      }

      if (json['success'] == true) {
        completer.complete(json['data']);
      } else {
        Logger.log('[SIDECAR] Error: ${json['error']}', show: true);

        completer.completeError(Exception(json['error']));
      }
    } catch (_, _) {
      Logger.log(line);
    }
  }

  @override
  Future<T> call<T>(
    String method, [
    Map<String, dynamic>? args,
    bool throwError = false,
  ]) async {
    if (!_initialized) {
      throw Exception('Sidecar bridge not initialized');
    }

    final process = _process;

    if (process == null) {
      throw Exception('Sidecar bridge not initialized');
    }

    final id = _nextId++;

    final completer = Completer<dynamic>();

    _pending[id] = completer;

    process.stdin.writeln(
      jsonEncode({'id': id, 'method': method, 'args': args ?? {}}),
    );

    try {
      final result = await completer.future.timeout(
        _callTimeout,
        onTimeout: () {
          _pending.remove(id);
          throw TimeoutException(
            'Sidecar call "$method" timed out',
            _callTimeout,
          );
        },
      );

      final decoded = _toDart(jsonDecode(result as String));

      if (decoded is List && decoded.every((e) => e is Map<String, dynamic>)) {
        return List<Map<String, dynamic>>.from(decoded) as T;
      }

      if (decoded is Map<String, dynamic>) {
        return decoded as T;
      }

      return decoded as T;
    } catch (e, c) {
      Logger.log('[SIDECAR] Call failed: $e\n$c', show: true);

      if (throwError) {
        rethrow;
      }

      return _emptyForType<T>();
    }
  }

  dynamic _toDart(dynamic value) {
    if (value is Map) {
      final result = <String, dynamic>{};

      value.forEach((k, v) {
        result[k.toString()] = _toDart(v);
      });

      return result;
    }

    if (value is List) {
      return value.map(_toDart).toList();
    }

    return value;
  }

  T _emptyForType<T>() {
    if (T == bool) return false as T;
    if (T == Map<String, dynamic>) {
      return <String, dynamic>{} as T;
    }
    if (T == List<Map<String, dynamic>>) {
      return <Map<String, dynamic>>[] as T;
    }

    return null as T;
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();

    _process?.kill();

    for (final c in _pending.values) {
      c.completeError(Exception('Bridge disposed'));
    }

    _pending.clear();

    _process = null;

    _initialized = false;
  }
}
