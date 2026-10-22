import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

bool _zipIntact(String path) {
  final input = InputFileStream(path);
  try {
    final archive = ZipDecoder().decodeStream(input);
    var files = 0;
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final bytes = entry.readBytes();
      final crc = entry.crc32;
      if (bytes == null || (crc != null && getCrc32(bytes) != crc)) {
        return false;
      }
      files++;
      entry.clear();
    }
    return files > 0;
  } catch (_) {
    return false;
  } finally {
    input.closeSync();
  }
}

Future<bool> zipIsIntact(String path) => compute(_zipIntact, path);
