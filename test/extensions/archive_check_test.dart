import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dartotsu_extension_bridge/Extensions/ArchiveCheck.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('archive_check'));
  tearDown(() => dir.deleteSync(recursive: true));

  List<int> build() {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('a.txt', List.filled(5000, 7)))
      ..addFile(
        ArchiveFile.bytes(
          'b.bin',
          List.generate(60000, (i) => (i * 31 + i ~/ 7) & 0xff),
        ),
      );
    return ZipEncoder().encode(archive);
  }

  test('a valid zip passes', () async {
    final file = File('${dir.path}/ok.jar')..writeAsBytesSync(build());
    expect(await zipIsIntact(file.path), isTrue);
  });

  test('a zip with damaged content fails', () async {
    final bytes = build();
    final mid = bytes.length ~/ 2;
    for (var i = mid; i < mid + 100; i++) {
      bytes[i] = bytes[i] ^ 0xff;
    }
    final file = File('${dir.path}/bad.jar')..writeAsBytesSync(bytes);
    expect(await zipIsIntact(file.path), isFalse);
  });

  test('a truncated zip fails', () async {
    final bytes = build();
    final file = File('${dir.path}/cut.jar')
      ..writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
    expect(await zipIsIntact(file.path), isFalse);
  });
}
