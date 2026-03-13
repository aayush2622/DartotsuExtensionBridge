import 'dart:async';
import 'dart:convert';

import 'package:fjs/fjs.dart';

import '../../../JsEngine.dart';
import 'BridgeRegister.dart';
import 'Utils.dart';

class JsExtensionEngine {
  JsExtensionEngine._internal();
  static final JsExtensionEngine instance = JsExtensionEngine._internal();

  late final JsEngine _engine;
  Completer<void>? _initCompleter;

  Future<void> init() {
    if (_initCompleter?.isCompleted ?? false) {
      return _initCompleter!.future;
    }

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    _doInit();
    return _initCompleter!.future;
  }

  Future<void> _doInit() async {
    try {
      await LibFjs.init();

      var context = await JsEngineEnv.instance.init();

      _engine = JsEngine(context: context);

      await _engine.init(
        bridge: (JsValue value) async {
          final data = value.value;

          if (data is Map && data['type'] != null) {
            return BridgeReg.call(data['type'], data);
          }

          return const JsResult.err(
            JsError.cancelled("Unknown bridge call"),
          );
        },
      );
      await JsUtils(_engine).init();
      _initCompleter?.complete();
    } catch (e, stack) {
      _initCompleter?.completeError(e, stack);
      _initCompleter = null;
    }
  }

  Future<void> loadModule({
    required String moduleName,
    required String sourceCode,
  }) async {
    await init();

    final wrapped = '''
$sourceCode
const __exports = {};

// Common
if (typeof searchResults === 'function')
  __exports.searchResults = searchResults;

if (typeof extractDetails === 'function')
  __exports.extractDetails = extractDetails;

// Anime
if (typeof extractEpisodes === 'function')
  __exports.extractEpisodes = extractEpisodes;

if (typeof extractStreamUrl === 'function')
  __exports.extractStreamUrl = extractStreamUrl;

// Manga
if (typeof extractChapters === 'function')
  __exports.extractChapters = extractChapters;

if (typeof extractImages === 'function')
  __exports.extractImages = extractImages;

export default __exports;
''';

    await _engine.declareNewModule(
      module: JsModule(
        name: moduleName,
        source: JsCode.code(wrapped),
      ),
    );
  }

  Future<JsValue> call({
    required String moduleName,
    required String method,
    List<dynamic> params = const [],
  }) async {
    await init();

    final encodedParams = jsonEncode(params);

    final js = '''
    (async () => {
      const module = await import('$moduleName');
      const target = module.default ?? module;

      if (!target)
        throw new Error("Module has no exports");

      const fn = target["$method"];

      if (typeof fn !== "function")
        throw new Error("Method '$method' not found");

      const args = JSON.parse('$encodedParams');
      return await fn(...args);
    })()
    ''';

    return await _engine.eval(source: JsCode.code(js));
  }

  Future<void> dispose() async {
    await _engine.dispose();

    _initCompleter = null;
  }
}
