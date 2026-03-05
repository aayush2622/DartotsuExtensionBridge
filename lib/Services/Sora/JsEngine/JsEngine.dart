import 'dart:async';
import 'dart:convert';

import 'package:fjs/fjs.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';

import '../../../dartotsu_extension_bridge.dart';
import '../../Mangayomi/http/m_client.dart';
import 'FetchV2.dart';

final _client = MClient.init();
Future<void> run() async {
  var manager = Get.find<ExtensionManager>().current.value;
}

class JsExtensionEngine {
  JsExtensionEngine._internal();
  static final JsExtensionEngine instance = JsExtensionEngine._internal();

  late final JsEngine _engine;
  late final FetchV2 _fetch;

  Completer<void>? _initCompleter;
  final Set<String> _loadedModules = {};

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

      final runtime = await JsAsyncRuntime.withOptions(
        builtin: JsBuiltinOptions.all(),
      );

      await runtime.setMemoryLimit(
        limit: BigInt.from(32 * 1024 * 1024),
      );

      await runtime.setGcThreshold(
        threshold: BigInt.from(8 * 1024 * 1024),
      );

      final context = await JsAsyncContext.from(runtime: runtime);

      _engine = JsEngine(context: context);
      _fetch = FetchV2(_engine);

      await _engine.init(
        bridge: (JsValue value) async {
          final data = value.value;

          if (data is Map && data['type'] == 'fetchv2') {
            return _fetch.handle(data);
          }

          return const JsResult.err(
            JsError.cancelled('Unknown bridge call'),
          );
        },
      );

      await _fetch.inject();

      _initCompleter?.complete();
    } catch (e, stack) {
      _initCompleter?.completeError(e, stack);
      _initCompleter = null; // allow retry
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

    _loadedModules.add(moduleName);
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

  void dispose() {
    _engine.dispose();
    _loadedModules.clear();
    _initCompleter = null;
  }
}
