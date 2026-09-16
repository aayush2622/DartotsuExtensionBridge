import 'dart:io';

/// Whether [file] starts with a ZIP/JAR local-file-header signature
/// (`PK\x03\x04`, `PK\x05\x06` for an empty archive, or `PK\x07\x08` for a
/// spanned archive).
///
/// A repo URL that doesn't actually point at a jar (an HTML error page, a
/// JSON catalog, ...) still downloads with a 200 and gets written to disk -
/// only the native dex2jar/JVM side eventually notices, deep in verbose logs,
/// leaving the UI showing zero sources with no visible error. Checking the
/// magic bytes right after download lets `addRepo` fail loudly instead.
Future<bool> hasZipSignature(File file) async {
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    final header = await raf.read(4);
    if (header.length < 4 || header[0] != 0x50 || header[1] != 0x4B) {
      return false;
    }
    return (header[2] == 0x03 && header[3] == 0x04) ||
        (header[2] == 0x05 && header[3] == 0x06) ||
        (header[2] == 0x07 && header[3] == 0x08);
  } catch (_) {
    return false;
  } finally {
    await raf?.close();
  }
}
