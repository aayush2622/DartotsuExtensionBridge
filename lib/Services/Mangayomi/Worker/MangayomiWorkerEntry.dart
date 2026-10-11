import 'dart:isolate';

import '../../../Engines/Worker/IsolateRpc.dart';
import '../../../Engines/Worker/WorkerHttp.dart';
import '../../../Engines/Worker/WorkerIsolate.dart';
import '../../../Logger.dart';
import '../../../NetworkClient.dart';
import '../Eval/dart/model/filter.dart';
import '../Models/Source.dart';
import '../Util/extension_preferences_providers.dart';
import '../Util/host_hooks.dart';
import '../Util/lib.dart';
import 'MangayomiCodec.dart';

/// Keeps a snapshot of the preferences the host sent with the current call.
/// Writes update the snapshot and are forwarded to the host, which owns the
/// database.
class _SnapshotPrefKv implements PrefKv {
  _SnapshotPrefKv(this._rpc);

  final IsolateRpc _rpc;
  final Map<String, dynamic> _data = {};

  void apply(Map snapshot) {
    snapshot.forEach((key, value) => _data[key as String] = value);
  }

  @override
  T? get<T>(String key) {
    final value = _data[key];
    if (value == null) return null;
    if (value is T) return value;
    if (value is List && T == List<String>) {
      return List<String>.from(value) as T;
    }
    return value as T?;
  }

  @override
  void set(String key, dynamic value) {
    _data[key] = value;
    _rpc.notify('kv.set', [key, value]);
  }
}

final _sources = <String, MSource>{};
late final _SnapshotPrefKv _kv;

void mangayomiWorkerMain(SendPort host) {
  final rpc = startWorkerEndpoint(host, _handle);

  _kv = _SnapshotPrefKv(rpc);
  prefKv = _kv;
  Logger.sink = (message, show) => rpc.notify('log', [message, show]);
  MClient.clientFactoryOverride = (reqcopyWith) =>
      RpcHttpClient(rpc, reqcopyWith);
  MangayomiHostHooks.tempDirPath = () => rpc.call<String>('tempDir');
  MangayomiHostHooks.evaluateInWebview = (url, headers, scripts, time) =>
      rpc.call<String>('webview', [url, headers, scripts, time]);
}

Future<Object?> _handle(String method, List args) async {
  switch (method) {
    case 'call':
      return _call(args);
    case 'invalidate':
      final id = args[0] as String;
      invalidateExtensionService(id);
      _sources.remove(id);
      knownSources.remove(id);
      return null;
    case 'disposeAll':
      disposeAllExtensionServices();
      _sources.clear();
      knownSources.clear();
      return null;
  }
  throw UnsupportedError('Unknown worker method: $method');
}

Future<Object?> _call(List args) async {
  final id = args[0] as String;
  final sourceJson = args[1] as Map?;
  final op = args[2] as String;
  final opArgs = args[3] as List;
  final prefs = args[4] as Map;

  if (sourceJson != null) {
    final source = MSource.fromJson(Map<String, dynamic>.from(sourceJson));
    _sources[id] = source;
    knownSources[id] = source;
  }

  final source = _sources[id];
  if (source == null) throw RpcRemoteError('NeedSource', id);

  _kv.apply(prefs);

  final service = getExtensionService(source);
  try {
    switch (op) {
      case 'getHeaders':
        return service.getHeaders();
      case 'getPopular':
        return encodeMPages(await service.getPopular(opArgs[0] as int));
      case 'getLatestUpdates':
        return encodeMPages(await service.getLatestUpdates(opArgs[0] as int));
      case 'search':
        return encodeMPages(
          await service.search(
            opArgs[0] as String,
            opArgs[1] as int,
            fromJsonFilterValuesToList(opArgs[2] as List),
          ),
        );
      case 'getDetail':
        return encodeMManga(await service.getDetail(opArgs[0] as String));
      case 'getPageList':
        return encodePageUrls(await service.getPageList(opArgs[0] as String));
      case 'getVideoList':
        return encodeVideos(await service.getVideoList(opArgs[0] as String));
      case 'getHtmlContent':
        return await service.getHtmlContent(
          opArgs[0] as String,
          opArgs[1] as String,
        );
      case 'getSourcePreferences':
        return encodePreferences(service.getSourcePreferences());
    }
    throw UnsupportedError('Unknown operation: $op');
  } finally {
    releaseExtensionService(source, service);
  }
}
