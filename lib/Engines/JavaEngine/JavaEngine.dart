import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:jni/jni.dart';

import '../../Logger.dart';
import '../../dartotsu_extension_bridge.dart';
import 'JavaHandler.dart';

class JavaEngine {
  SendPort? _sendPort;
  Isolate? _isolate;
  bool _initialized = false;

  Future<void> init({
    required String pluginJarPath,
    required JavaHandler handler,
  }) async {
    if (_initialized) return;

    final receivePort = ReceivePort();

    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/jni',
    );

    final jniJarPath = "${dir!.path}/jni.jar";

    final jniJarCache = await rootBundle.load(
      "packages/dartotsu_extension_bridge/assets/jni/jni.jar",
    );

    String libName;
    String assetName;

    if (Platform.isWindows) {
      libName = "dartjni.dll";
      assetName = "packages/dartotsu_extension_bridge/assets/jni/dartjni.dll";
    } else {
      libName = "libdartjni.so";
      assetName = "packages/dartotsu_extension_bridge/assets/jni/libdartjni.so";
    }

    final libPath = "${dir.path}/$libName";
    final libCache = await rootBundle.load(assetName);
    await _ensureFile(libPath, libCache);
    await _ensureFile(jniJarPath, jniJarCache);

    _isolate = await Isolate.spawn(_entry, {
      "sendPort": receivePort.sendPort,
      "handler": handler,
      "jniJar": jniJarPath,
      "libPath": libPath,
      "pluginJar": pluginJarPath,
    });

    _sendPort = await receivePort.first as SendPort;
    _initialized = true;
  }

  Future<void> _ensureFile(String path, ByteData data) async {
    final file = File(path);

    if (await file.exists()) return;

    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _initialized = false;
  }

  Future<T> call<T>(
    String method, [
    Map<String, dynamic>? args,
    bool throwError = false,
  ]) async {
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
      }

      Logger.log("JNI Error: ${result["error"]}", show: true);

      Logger.log(result["stack"]);

      return _emptyForType<T>();
    }

    final data = result["data"];

    if (data is String) {
      try {
        final decoded = jsonDecode(data);

        if (decoded is List) {
          return decoded.map((e) => Map<String, dynamic>.from(e)).toList() as T;
        }

        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded) as T;
        }

        return decoded as T;
      } catch (_) {}
    }

    return data as T;
  }

  static void _entry(Map args) async {
    final mainSendPort = args["sendPort"] as SendPort;
    final handler = args["handler"] as JavaHandler;

    final jniJar = args["jniJar"] as String;
    final libPath = args["libPath"] as String;
    final pluginJar = args["pluginJar"] as String;

    final port = ReceivePort();

    mainSendPort.send(port.sendPort);

    Jni.spawnIfNotExists(
      classPath: [jniJar, pluginJar],
      dylibDir: File(libPath).parent.path,
      jvmOptions: [
        "-Dfile.encoding=UTF-8",
        "-Xms128m",
        "-Xmx512m",
        "-XX:+UseG1GC",
      ],
    );

    await for (final msg in port) {
      final replyTo = msg["replyTo"] as SendPort;

      try {
        final result = await handler.handle(
          msg["method"] as String,
          Map<String, dynamic>.from(msg["args"]),
        );

        replyTo.send({"ok": true, "data": _toDart(result)});
      } catch (e, st) {
        replyTo.send({
          "ok": false,
          "error": e.toString(),
          "stack": st.toString(),
        });
      }
    }
  }

  static dynamic _toDart(dynamic value) {
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
}
