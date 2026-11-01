import 'dart:async';
import 'dart:io';

import 'package:dartotsu_extension_bridge/downloads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory dir;
  final body = List<int>.generate(300000, (i) => i % 251);
  var rangeRequests = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bridge_dl');
    rangeRequests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/missing') {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final range = req.headers.value('range');
      if (range == null) {
        req.response.headers.contentLength = body.length;
        req.response.add(body);
      } else {
        rangeRequests++;
        final start = int.parse(range.split('=')[1].split('-')[0]);
        req.response.statusCode = 206;
        req.response.headers.set(
          'content-range',
          'bytes $start-${body.length - 1}/${body.length}',
        );
        req.response.headers.contentLength = body.length - start;
        req.response.add(body.sublist(start));
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  String url() => 'http://127.0.0.1:${server.port}/file.bin';

  test('fetchFile saves a whole file and reports progress', () async {
    final target = File('${dir.path}/a.bin');
    var last = 0;
    await fetchFile(
      url: url(),
      target: target,
      cancel: DownloadCancel(),
      onProgress: (received, total) => last = received,
    );
    expect(await target.readAsBytes(), body);
    expect(last, body.length);
    expect(File('${target.path}.part').existsSync(), isFalse);
  });

  test('fetchFile resumes a partial download with a Range request', () async {
    final target = File('${dir.path}/b.bin');
    await File('${target.path}.part').writeAsBytes(body.sublist(0, 100000));
    await fetchFile(
      url: url(),
      target: target,
      cancel: DownloadCancel(),
      onProgress: (_, _) {},
    );
    expect(rangeRequests, 1);
    expect(await target.readAsBytes(), body);
  });

  test('a cancelled download fails and leaves no finished file', () async {
    final target = File('${dir.path}/c.bin');
    final cancel = DownloadCancel();
    unawaited(cancel.cancel());
    await expectLater(
      fetchFile(
        url: url(),
        target: target,
        cancel: cancel,
        onProgress: (_, _) {},
      ),
      throwsA(anything),
    );
    expect(target.existsSync(), isFalse);
  });

  test('readText throws on an HTTP error', () async {
    await expectLater(
      readText('http://127.0.0.1:${server.port}/missing'),
      throwsA(isA<HttpStatusError>()),
    );
  });

  test('file names are made safe and numbered', () {
    expect(safeName('Re:Zero / Season 2?'), 'Re Zero Season 2');
    expect(numberLabel(7), '007');
    expect(numberLabel(7.5), '007.5');
    expect(
      unitFileName(video: true, number: 3, unitKey: '3', title: 'x'),
      'Episode 003',
    );
  });
}
