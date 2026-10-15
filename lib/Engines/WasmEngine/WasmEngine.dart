import 'dart:typed_data';

import 'package:wasd/wasm.dart';

class WasmEngine {
  WasmEngine._(this._instance);

  final Instance _instance;

  static Future<WasmEngine> instantiate(
    Uint8List bytes, [
    Imports imports = const {},
  ]) async {
    final module = Module(Uint8List.fromList(bytes).buffer);
    return WasmEngine._(Instance(module, imports));
  }

  Exports get exports => _instance.exports;

  bool hasExport(String name) => exports[name] is FunctionImportExportValue;

  Memory? get memory {
    final export = exports['memory'];
    return export is MemoryImportExportValue ? export.ref : null;
  }

  Future<Object?> call(String name, [List<Object?> args = const []]) async {
    final export = exports[name];
    if (export is! FunctionImportExportValue) {
      throw ArgumentError('No exported function named "$name"');
    }
    final result = export.ref(args);
    return result is Future ? await result : result;
  }

  Uint8List readBytes(int ptr, int length) {
    final mem = memory;
    if (mem == null) throw StateError('Module has no exported memory');
    return Uint8List.fromList(mem.buffer.asUint8List(ptr, length));
  }

  void writeBytes(int ptr, List<int> bytes) {
    final mem = memory;
    if (mem == null) throw StateError('Module has no exported memory');
    mem.buffer.asUint8List(ptr, bytes.length).setAll(0, bytes);
  }
}
