import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:jni/jni.dart';

import '../Logger.dart';
import '../dartotsu_extension_bridge.dart';

class JavaEngine {
  SendPort? _sendPort;
  Isolate? _isolate;
  bool _initialized = false;
  static ByteData? _jniJarCache;
  static ByteData? _soCache;

  Future<void> init({
    required String engineJarPath,
    required Future<dynamic> Function(String, Map<String, dynamic>) handler,
  }) async {
    if (_initialized) return;

    final receivePort = ReceivePort();

    final dir = await DartotsuExtensionBridge.context
        .getDirectory(subPath: 'bridge/jni');

    final jniJarPath = "${dir!.path}/jni.jar";
    final soPath = "${dir.path}/libdartjni.so";

    _jniJarCache ??= await rootBundle.load(
      "packages/dartotsu_extension_bridge/assets/jni/jni.jar",
    );
    _soCache ??= await rootBundle.load(
      "packages/dartotsu_extension_bridge/assets/jni/libdartjni.so",
    );

    await _ensureFile(jniJarPath, _jniJarCache!);
    await _ensureFile(soPath, _soCache!);

    _isolate = await Isolate.spawn(
      _entry,
      {
        "sendPort": receivePort.sendPort,
        "handler": handler,
        "jniJar": jniJarPath,
        "soFile": soPath,
        "engineJar": engineJarPath,
      },
    );

    _sendPort = await receivePort.first as SendPort;
    _initialized = true;
  }

  Future<void> _ensureFile(String path, ByteData data) async {
    final file = File(path);
    if (await file.exists()) return;

    await file.writeAsBytes(
      data.buffer.asUint8List(),
      flush: true,
    );
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _initialized = false;
  }

  Future<T> call<T>(String method,
      [Map<String, dynamic>? args, bool throwError = false]) async {
    if (!_initialized) {
      throw Exception("JavaEngine not initialized");
    }

    final responsePort = ReceivePort();

    _sendPort!.send({
      "method": method,
      "args": args ?? {},
      "replyTo": responsePort.sendPort,
    });

    final result = await responsePort.first as Map;

    if (result["ok"] != true) {
      if (throwError) {
        throw Exception(result["error"]);
      } else {
        Logger.log("JNI Error: ${result["error"]}", show: true);
        Logger.log(result["stack"]);
        return _emptyForType<T>();
      }
    }
    var data = result["data"];
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

  T _emptyForType<T>() {
    if (T == bool) return false as T;
    if (T == List<Map<String, dynamic>>) {
      return <Map<String, dynamic>>[] as T;
    }
    if (T == Map<String, dynamic>) {
      return <String, dynamic>{} as T;
    }
    return null as T;
  }

  void _entry(Map args) async {
    final mainSendPort = args["sendPort"] as SendPort;
    final handler = args["handler"] as Future<dynamic> Function(
      String,
      Map<String, dynamic>,
    );

    final jniJar = args["jniJar"] as String;
    final soFile = args["soFile"] as String;

    final port = ReceivePort();
    mainSendPort.send(port.sendPort);

    final engineJar = args["engineJar"] as String;

    Jni.spawnIfNotExists(
      classPath: [jniJar, engineJar],
      jvmOptions: [
        "-Dfile.encoding=UTF-8",
        "-Xms128m",
        "-Xmx512m",
        "-XX:+UseG1GC",
        "-XX:MaxGCPauseMillis=200",
      ],
      dylibDir: File(soFile).parent.path,
    );

    await for (final msg in port) {
      final replyTo = msg["replyTo"] as SendPort;
      final method = msg["method"] as String;
      final args = msg["args"] as Map<String, dynamic>;

      try {
        final result = await handler(method, args);

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

  dynamic _toDart(dynamic value) {
    if (value == null) return null;
    if (value is JObject) {
      try {
        return value.toString();
      } catch (_) {
        return null;
      }
    }
    if (value is JString) {
      try {
        final str = value.toDartString(releaseOriginal: true);
        return str;
      } catch (e) {
        Logger.log("Invalid JString detected: $e");
        return null;
      }
    }
    if (value is JBoolean) return value.toDartBool(releaseOriginal: true);
    if (value is JInteger) return value.toDartInt(releaseOriginal: true);
    if (value is JDouble) return value.toDartDouble(releaseOriginal: true);
    if (value is JFloat) return value.toDartDouble(releaseOriginal: true);
    if (value is JLong) return value.toDartInt(releaseOriginal: true);

    if (value is JList) {
      final dartList = value.asDart().map(_toDart).toList();

      value.release();
      return dartList;
    }
    if (value is JMap) {
      final dartMap = value.asDart();

      final result = <String, dynamic>{};

      dartMap.forEach((k, v) {
        final key = _toDart(k);
        result[key is String ? key : key.toString()] = _toDart(v);
      });

      value.release();

      return result;
    }

    return value;
  }
}
