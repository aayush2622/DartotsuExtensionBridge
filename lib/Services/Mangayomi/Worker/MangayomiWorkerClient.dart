import 'dart:async';

import 'package:path_provider/path_provider.dart';

import '../../../Engines/Worker/IsolateRpc.dart';
import '../../../Engines/Worker/WorkerHttp.dart';
import '../../../Engines/Worker/WorkerIsolate.dart';
import '../../../Logger.dart';
import '../../../Settings/KvStore.dart';
import '../Eval/dart/model/m_bridge.dart';
import '../Models/Source.dart';
import '../Util/extension_preferences_providers.dart' show extractSourceId;
import 'MangayomiCodec.dart';
import 'MangayomiWorkerEntry.dart';

/// Host-side handle to the Mangayomi worker isolate. One instance for the
/// whole backend: every source's interpreter work (JS/Dart eval, repo
/// parsing's `compute()` calls aside) runs in this single worker rather than
/// blocking the UI isolate, since Mangayomi's JS/d4rt evaluation is what was
/// observed to stall the app on fetches.
class MangayomiWorkerClient {
  MangayomiWorkerClient._()
    : _worker = WorkerIsolate(
        name: 'mangayomi-extensions',
        entry: mangayomiWorkerMain,
        hostHandler: _serveHostCall,
      );

  static final instance = MangayomiWorkerClient._();

  final WorkerIsolate _worker;

  /// Which source id's data is currently loaded in the worker, so a call for
  /// a different source re-sends it instead of hitting [RpcRemoteError].
  String? _loadedSourceId;

  Future<T> call<T>(MSource source, String op, List args) async {
    final sendSource = _loadedSourceId != source.id;
    final prefs = _snapshotPreferences(source);

    try {
      final result = await _worker.call<Object?>('call', [
        source.id,
        sendSource ? source.toJson() : null,
        op,
        args,
        prefs,
      ]);
      _loadedSourceId = source.id;
      return _decode<T>(op, result);
    } on RpcRemoteError catch (e) {
      if (e.type == 'NeedSource') {
        _loadedSourceId = null;
        return call<T>(source, op, args);
      }
      rethrow;
    }
  }

  /// Everything `getSourcePreferenceEntry`/`getSourcePreferenceStringValue`
  /// (both reachable from inside the worker, via a source's JS/Dart `get`,
  /// `getString`, `setString` calls) might read for this source - keyed two
  /// different ways (`sourcePrefs_<numericId>` vs
  /// `sourcePrefString_<fullId>_<key>`), so both prefixes are sent.
  Map<String, dynamic> _snapshotPreferences(MSource source) {
    final numericId = extractSourceId(source.id!).toString();
    return {
      ...getValsWithPrefix('sourcePrefs_$numericId'),
      ...getValsWithPrefix('sourcePrefString_${source.id}_'),
    };
  }

  void invalidate(String? sourceId) {
    if (sourceId != null && sourceId == _loadedSourceId) {
      _loadedSourceId = null;
    }
    if (_worker.isRunning) _worker.notify('invalidate', [sourceId]);
  }

  Future<void> disposeAll() async {
    _loadedSourceId = null;
    if (_worker.isRunning) _worker.notify('disposeAll');
  }

  T _decode<T>(String op, Object? result) {
    final decoded = switch (op) {
      'getPopular' ||
      'getLatestUpdates' ||
      'search' => decodeMPages(result as Map),
      'getDetail' => decodeMManga(result as Map),
      'getPageList' => decodePageUrls(result as List),
      'getVideoList' => decodeVideos(result as List),
      'getSourcePreferences' => decodePreferences(result as List),
      _ => result,
    };
    return decoded as T;
  }
}

Future<Object?> _serveHostCall(String method, List args) {
  switch (method) {
    case httpRpcMethod:
      return serveHttpRpc(args);
    case 'tempDir':
      return getTemporaryDirectory().then((d) => d.path);
    case 'webview':
      return MBridge.evaluateJavascriptViaWebview(
        args[0] as String,
        Map<String, String>.from(args[1] as Map),
        List<String>.from(args[2] as List),
        time: args[3] as int,
      );
    case 'log':
      Logger.log(args[0] as String, show: args[1] as bool);
      return Future.value();
    case 'kv.set':
      setVal(args[0] as String, args[1]);
      return Future.value();
  }
  throw UnsupportedError('Unknown host call: $method');
}
