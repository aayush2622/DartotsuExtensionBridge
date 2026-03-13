import 'dart:async';

import 'package:fjs/fjs.dart';

class JsEngineEnv {
  JsEngineEnv._internal();
  static final JsEngineEnv instance = JsEngineEnv._internal();

  late final JsAsyncRuntime _runtime;
  late final JsAsyncContext _context;

  Completer<JsAsyncContext>? _contextCompleter;

  Future<JsAsyncContext> init() {
    if (_contextCompleter != null) {
      return _contextCompleter!.future;
    }

    _contextCompleter = Completer<JsAsyncContext>();
    _doInit();
    return _contextCompleter!.future;
  }

  Future<void> _doInit() async {
    try {
      await LibFjs.init();

      _runtime = await JsAsyncRuntime.withOptions(
        builtin: JsBuiltinOptions.all(),
      );

      await _runtime.setMemoryLimit(
        limit: BigInt.from(64 * 1024 * 1024),
      );

      await _runtime.setGcThreshold(
        threshold: BigInt.from(16 * 1024 * 1024),
      );

      _context = await JsAsyncContext.from(runtime: _runtime);

      _contextCompleter?.complete(_context);
    } catch (e, stack) {
      _contextCompleter?.completeError(e, stack);
      _contextCompleter = null;
    }
  }

  JsAsyncContext get context {
    if (_contextCompleter == null || !_contextCompleter!.isCompleted) {
      throw StateError('JsExtensionEngine not initialized. Call init() first.');
    }
    return _context;
  }

  Future<void> dispose() async {
    if (_contextCompleter == null) return;

    try {
      while (await _runtime.executePendingJob()) {}

      await _runtime.runGc();
    } catch (_) {}

    _context.dispose();
    _runtime.dispose();

    _contextCompleter = null;
  }
}
