import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../Logger.dart';
import '../JavaInstaller.dart';
import 'JavaBridge.dart';

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

  // Remembered so `call()` can restart a sidecar that died or never started.
  String? _pluginJarPath;

  Future<void>? _starting;

  @override
  Future<void> init({required String pluginJarPath}) async {
    _pluginJarPath = pluginJarPath;
    if (_initialized) return;

    // Concurrent callers share a single start instead of spawning several JVMs.
    final inFlight = _starting;
    if (inFlight != null) return inFlight;

    final start = _start(pluginJarPath);
    _starting = start;
    try {
      await start;
    } finally {
      _starting = null;
    }
  }

  Future<void> _start(String pluginJarPath) async {
    Logger.log('Starting sidecar: $pluginJarPath');
    final javaPath = await JavaRuntimeManager.ensureInstalled();

    if (javaPath == null) throw Exception('Java runtime not found');

    final process = _process = await Process.start(javaPath, [
      '-Dfile.encoding=UTF-8',
      '-Dsun.stdout.encoding=UTF-8',
      '-Dsun.stderr.encoding=UTF-8',
      '-Xms128m',
      '-Xmx1536m',
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
      process.exitCode.then((code) {
        Logger.log('Sidecar exited with code $code');

        // A replacement sidecar may already be running; don't clobber it.
        if (!identical(_process, process)) return;

        // Without this, every call() made after the sidecar dies still
        // passes the `_initialized` guard, writes to a dead stdin, and
        // waits out the full _callTimeout with no chance of a response -
        // this makes those calls fail immediately instead.
        _initialized = false;
        _process = null;

        for (final c in _pending.values) {
          if (!c.isCompleted) {
            c.completeError(_SidecarExited(code));
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
    } catch (_) {
      Logger.log(line);
    }
  }

  @override
  Future<T> call<T>(
    String method, [
    Map<String, dynamic>? args,
    bool throwError = false,
  ]) async {
    if (!_initialized || _process == null) {
      final jar = _pluginJarPath;
      if (jar == null) throw Exception('Sidecar bridge not initialized');
      Logger.log('Sidecar not running, restarting');
      await init(pluginJarPath: jar);
    }

    try {
      return await _callOnce<T>(method, args, throwError);
    } on _SidecarExited catch (e) {
      // The sidecar died mid-call: restart it once and retry.
      final jar = _pluginJarPath;
      if (jar == null) {
        if (throwError) rethrow;
        return emptyJavaBridgeValue<T>();
      }
      Logger.log('Sidecar died during "$method" ($e), restarting', show: true);
      try {
        await init(pluginJarPath: jar);
        return await _callOnce<T>(method, args, throwError);
      } catch (e2) {
        if (throwError) rethrow;
        return emptyJavaBridgeValue<T>();
      }
    }
  }

  Future<T> _callOnce<T>(
    String method,
    Map<String, dynamic>? args,
    bool throwError,
  ) async {
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

      final text = result as String;
      final decoded = text.trim().isEmpty ? null : _toDart(jsonDecode(text));

      if (decoded is List && decoded.every((e) => e is Map<String, dynamic>)) {
        return List<Map<String, dynamic>>.from(decoded) as T;
      }

      if (decoded is Map<String, dynamic>) {
        return decoded as T;
      }

      return decoded as T;
    } on _SidecarExited {
      rethrow;
    } catch (e, c) {
      Logger.log('[SIDECAR] Call failed: $e\n$c', show: true);

      if (throwError) {
        rethrow;
      }

      return emptyJavaBridgeValue<T>();
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

    // Explicit disposal must not be undone by the auto-restart path.
    _pluginJarPath = null;
  }


  static const _exitTimeout = Duration(seconds: 10);

  @override
  Future<void> disposeAndAwaitExit() async {
    final process = _process;
    dispose();
    if (process == null) return;
    try {
      await process.exitCode.timeout(_exitTimeout);
    } catch (_) {
    }
  }
}

class _SidecarExited implements Exception {
  final int code;
  _SidecarExited(this.code);

  @override
  String toString() => 'Sidecar exited with code $code';
}
