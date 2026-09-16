import 'dart:io';
import 'dart:typed_data';

import 'package:dartotsu_extension_bridge/Services/Shared/ZipValidation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('zip_validation_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> writeBytes(List<int> bytes) async {
    final file = File('${tmp.path}/candidate.jar');
    await file.writeAsBytes(bytes);
    return file;
  }

  test('accepts a normal zip/jar local-file-header signature', () async {
    final file = await writeBytes([0x50, 0x4B, 0x03, 0x04, 0, 0]);
    expect(await hasZipSignature(file), isTrue);
  });

  test('accepts an empty archive (End Of Central Directory only)', () async {
    final file = await writeBytes([0x50, 0x4B, 0x05, 0x06, 0, 0]);
    expect(await hasZipSignature(file), isTrue);
  });

  test('rejects a JSON response saved with a .jar extension', () async {
    final file = await writeBytes(utf8Bytes('{"sites": []}'));
    expect(await hasZipSignature(file), isFalse);
  });

  test('rejects an HTML error page', () async {
    final file = await writeBytes(utf8Bytes('<!DOCTYPE html><html></html>'));
    expect(await hasZipSignature(file), isFalse);
  });

  test('rejects an empty file', () async {
    final file = await writeBytes(const []);
    expect(await hasZipSignature(file), isFalse);
  });

  test('rejects a nonexistent file instead of throwing', () async {
    final file = File('${tmp.path}/missing.jar');
    expect(await hasZipSignature(file), isFalse);
  });
}

List<int> utf8Bytes(String s) => Uint8List.fromList(s.codeUnits);
