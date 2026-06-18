import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:jni/jni.dart';

import '../../../ExtensionBridge.dart';
import '../../../Logger.dart';
import '../JavaHandler.dart';
import '../JavaInstaller.dart';

abstract class JavaBridge {
  Future<void> init({
    required String pluginJarPath,
    required JavaHandler handler,
  });

  Future<T> call<T>(
    String method, [
    Map<String, dynamic>? args,
    bool throwError = false,
  ]);

  void dispose();
}

class JniBridge implements JavaBridge {
  SendPort? _sendPort;
  Isolate? _isolate;
  bool _initialized = false;

  @override
  Future<void> init({
    required String pluginJarPath,
    required JavaHandler handler,
  }) async {
    if (_initialized) return;

    final receivePort = ReceivePort();

    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/jni',
    );

    if (dir == null) {
      throw Exception('Failed to get JNI directory');
    }

    final isWindows = Platform.isWindows;

    final libName = isWindows ? 'dartjni.dll' : 'libdartjni.so';
    final libAsset = 'packages/dartotsu_extension_bridge/assets/jni/$libName';

    final libPath = '${dir.path}/$libName';
    final jniJarPath = '${dir.path}/jni.jar';

    await Future.wait([
      _ensureFile(libPath, await rootBundle.load(libAsset)),
      _ensureFile(
        jniJarPath,
        await rootBundle.load(
          'packages/dartotsu_extension_bridge/assets/jni/jni.jar',
        ),
      ),
    ]);

    final javaPath = await JavaRuntimeManager.ensureInstalled();

    final jvmPath = javaPath == 'java'
        ? null
        : await JavaRuntimeManager.getJvmPath();

    _isolate = await Isolate.spawn(_entry, <String, dynamic>{
      'sendPort': receivePort.sendPort,
      'handler': handler,
      'jniJar': jniJarPath,
      'libPath': libPath,
      'pluginJar': pluginJarPath,
      'jvmPath': jvmPath,
    });

    _sendPort = await receivePort.first as SendPort;
    receivePort.close();

    _initialized = true;
  }

  @override
  Future<T> call<T>(
    String method, [
    Map<String, dynamic>? args,
    bool throwError = false,
  ]) async {
    if (!_initialized) {
      throw Exception("JNI bridge not initialized");
    }

    final responsePort = ReceivePort();

    try {
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
        Logger.log("${result["error"]} ${result["stack"]}");
        return _emptyForType<T>();
      }

      final data = result["data"];

      if (data is String) {
        try {
          final decoded = jsonDecode(data);

          if (decoded is List) {
            return decoded.map((e) => Map<String, dynamic>.from(e)).toList()
                as T;
          }

          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded) as T;
          }

          return decoded as T;
        } catch (_) {}
      }

      return data as T;
    } finally {
      responsePort.close();
    }
  }

  @override
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _initialized = false;
  }

  Future<void> _ensureFile(String path, ByteData data) async {
    final file = File(path);

    //if (await file.exists()) return;

    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  static Future<void> _entry(Map<String, dynamic> args) async {
    final mainSendPort = args["sendPort"] as SendPort;
    final handler = args["handler"] as JavaHandler;

    final jniJar = args["jniJar"] as String;
    final libPath = args["libPath"] as String;
    final pluginJar = args["pluginJar"] as String;
    final jvmPath = args["jvmPath"] as String?;

    final port = ReceivePort();

    try {
      if (jvmPath != null) {
        ffi.DynamicLibrary.open(jvmPath);
        debugPrint("Loaded JVM: $jvmPath");
      }
      Jni.setDylibDir(
        dylibDir: File(libPath).parent.path,
      );
      Jni.spawnIfNotExists(
        classPath: [jniJar, pluginJar],
        jvmOptions: const ["-Dfile.encoding=UTF-8", "-Xms128m", "-Xmx512m"],
      );

      mainSendPort.send(port.sendPort);
    } catch (e, st) {
      debugPrint("Failed to start JVM: $e\n$st");
      rethrow;
    }

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
