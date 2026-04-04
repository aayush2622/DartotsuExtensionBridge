import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:jni/jni.dart';

import '../../jni/com/aayush262/dartotsu_extension_bridge/AniyomiExtensionApi.dart';

class JniChannel {
  static final JniChannel instance = JniChannel._();

  JniChannel._();

  SendPort? _sendPort;
  Isolate? _jniIsolate;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    final receivePort = ReceivePort();

    _jniIsolate = await Isolate.spawn(
      _jniIsolateEntry,
      receivePort.sendPort,
    );

    _sendPort = await receivePort.first as SendPort;
    _initialized = true;
  }

  void dispose() {
    if (!_initialized) return;

    _jniIsolate?.kill(priority: Isolate.immediate);
    _jniIsolate = null;

    _sendPort = null;
    _initialized = false;
  }

  Future<T> invokeMethod<T>(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    if (!_initialized) {
      throw Exception("JniChannel not initialized");
    }

    final responsePort = ReceivePort();

    _sendPort!.send({
      "method": method,
      "args": args ?? {},
      "replyTo": responsePort.sendPort,
    });

    final result = await responsePort.first as Map;

    if (result["error"] != null) {
      print("JNI Error: ${result["error"]}");
      print(result["stack"]);
      return _emptyForType<T>();
    }

    final data = _toDart(result["data"]);

    if (data is String) {
      final decoded = jsonDecode(data);

      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList() as T;
      }

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded) as T;
      }

      return decoded as T;
    }

    return data as T;
  }
}

T _emptyForType<T>() {
  if (T == List<Map<String, dynamic>>) {
    return <Map<String, dynamic>>[] as T;
  }
  if (T == Map<String, dynamic>) {
    return <String, dynamic>{} as T;
  }
  return null as T;
}

void _jniIsolateEntry(SendPort mainSendPort) async {
  final port = ReceivePort();
  mainSendPort.send(port.sendPort);

  _JniRuntime.init();

  final bridge = AniyomiExtensionApi();

  await for (final msg in port) {
    if (msg is Map<String, dynamic>) {
      final replyTo = msg["replyTo"] as SendPort;
      final method = msg["method"] as String;
      final args = msg["args"] as Map<String, dynamic>;

      try {
        final result = await _handleMethod(bridge, method, args);

        replyTo.send({
          "ok": true,
          "data": _toDart(result),
        });
      } catch (e, st) {
        replyTo.send({
          "ok": false,
          "error": e.toString(),
          "stack": st.toString(),
        });
      }
    }
  }
}

dynamic _toDart(dynamic value) {
  if (value == null) return null;

  if (value is JString) return value.toDartString();
  if (value is JBoolean) return value.booleanValue();
  if (value is JInteger) return value.intValue();
  if (value is JDouble) return value.doubleValue();
  if (value is JFloat) return value.floatValue();
  if (value is JLong) return value.longValue();

  if (value is JList) {
    return value.toList().map(_toDart).toList();
  }

  if (value is JMap) {
    final map = <String, dynamic>{};
    value.forEach((k, v) {
      map[_toDart(k).toString()] = _toDart(v);
    });
    return map;
  }

  return value;
}

Future<dynamic> _handleMethod(
  AniyomiExtensionApi b,
  String method,
  Map<String, dynamic> args,
) async {
  switch (method) {
    case "initialize":
      b.initializeDesktop((args["path"] as String).toJString());
      return null;

    case "getInstalledAnimeExtensions":
      return await b.getInstalledAnimeExtensions(
        (args["path"] as String?)?.toJString(),
      );

    case "getInstalledMangaExtensions":
      return await b.getInstalledMangaExtensions(
        (args["path"] as String?)?.toJString(),
      );

    case "getPopular":
      return await b.getPopular(
        (args["sourceId"] as String).toJString(),
        args["isAnime"],
        args["page"],
      );

    case "search":
      return await b.search(
        (args["sourceId"] as String).toJString(),
        args["isAnime"],
        (args["query"] as String).toJString(),
        args["page"],
      );

    case "getDetail":
      return await b.getDetail(
        (args["sourceId"] as String).toJString(),
        args["isAnime"],
        (args["media"] as String).toJString(),
      );

    case "getVideoList":
      return await b.getVideoList(
        (args["sourceId"] as String).toJString(),
        args["isAnime"],
        (args["episode"] as String).toJString(),
      );

    case "getPageList":
      return await b.getPageList(
        (args["sourceId"] as String).toJString(),
        args["isAnime"],
        (args["episode"] as String).toJString(),
      );

    case "getPreference":
      return await b.getPreference(
        (args["sourceId"] as String).toJString(),
        args["isAnime"],
      );

    case "saveSourcePreference":
      return await b.saveSourcePreference(
        (args["sourceId"] as String).toJString(),
        (args["key"] as String).toJString(),
        (args["value"] as String?)?.toJString(),
      );

    default:
      throw Exception("Unknown method: $method");
  }
}

class _JniRuntime {
  static bool _started = false;

  static void init() {
    if (_started) return;

    Jni.spawnIfNotExists(
      classPath: [
        "/home/aayush/AndroidStudioProjects/DartotsuExtensionBridge/build/jni_libs/jni.jar",
        "/home/aayush/AndroidStudioProjects/DartotsuExtensionBridge/runtimeManager/builds/aniyomiDesktop/aniyomiDesktop.jar",
      ],
      dylibDir:
          "/home/aayush/AndroidStudioProjects/DartotsuExtensionBridge/build/jni_libs",
    );

    _started = true;
  }
}
