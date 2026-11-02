import 'dart:io';
import 'dart:typed_data';

import 'package:dartotsu_extension_bridge/Network/PageProxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serves fetched page bytes with a sniffed type', () async {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    final ok = await PageProxy.serve(() async => png);
    final bad = await PageProxy.serve(() async => throw StateError('nope'));
    final client = HttpClient();
    final res = await (await client.getUrl(Uri.parse(ok))).close();
    expect(res.statusCode, 200);
    expect(res.headers.contentType?.mimeType, 'image/png');
    final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    expect(body, png);
    final failed = await (await client.getUrl(Uri.parse(bad))).close();
    expect(failed.statusCode, 500);
    await failed.drain<void>();
    final missing = await (await client.getUrl(
      Uri.parse(ok.replaceAll(RegExp(r'[0-9a-f]{32}$'), 'x')),
    )).close();
    expect(missing.statusCode, 404);
    await missing.drain<void>();
    client.close();
  });
}
