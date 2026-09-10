import 'dart:io';
import 'dart:typed_data';

import 'package:dartotsu_extension_bridge/Services/Shared/TachiyomiRepo.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dpf_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test(
    'writes the body to destPath on 200 and leaves no .tmp behind',
    () async {
      final client = MockClient((req) async {
        return http.Response.bytes(
          Uint8List.fromList(List<int>.filled(2048, 0x42)),
          200,
        );
      });

      final dest = '${tmp.path}/ext.jar';
      await downloadPackageFile(client, 'https://host/ext.jar', dest);

      expect(await File(dest).length(), 2048);
      expect(await File('$dest.tmp').exists(), isFalse);
    },
  );

  test('throws on a non-200 and does not create the destination', () async {
    final client = MockClient((req) async => http.Response('nope', 404));

    final dest = '${tmp.path}/ext.jar';
    await expectLater(
      downloadPackageFile(client, 'https://host/ext.jar', dest),
      throwsA(isA<Exception>()),
    );
    expect(await File(dest).exists(), isFalse);
  });

  test('replaces an existing file rather than failing', () async {
    final dest = '${tmp.path}/ext.jar';
    await File(dest).writeAsBytes(List<int>.filled(10, 0));

    final client = MockClient((req) async {
      return http.Response.bytes(
        Uint8List.fromList(List<int>.filled(64, 0x01)),
        200,
      );
    });

    await downloadPackageFile(client, 'https://host/ext.jar', dest);
    expect(await File(dest).length(), 64);
  });
}
