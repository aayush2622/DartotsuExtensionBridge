import 'dart:convert';
import 'dart:io';

import 'package:dartotsu_extension_bridge/Services/LnReader/LnReaderWorker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

void main() {
  LnReaderWorker.clientFactory = () =>
      IOClient(HttpClient()..badCertificateCallback = (cert, host, port) => true);
  LnReaderWorker.logSink = (m) => print('[LOG] $m');
  LnReaderWorker.readStore = (_) => null;
  LnReaderWorker.writeStore = (_, __) {};

  test('lnori parseChapter alone (post contents/parents change)', () async {
    final code = await File('/tmp/lnreader-test/plugins/lnori.js').readAsString();
    final worker = await LnReaderWorker.spawn(sourceId: 'lnori', code: code);
    try {
      const chapterPath =
          'book/12040/re-zero-starting-life-in-another-world-vol-1#page11';
      final content = await worker.content(chapterPath);
      print('content length: ${content?.length}');
      expect(content, isNotNull);
    } finally {
      await worker.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
