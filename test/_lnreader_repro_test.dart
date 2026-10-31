import 'dart:io';

import 'package:dartotsu_extension_bridge/Models/DMedia.dart';
import 'package:dartotsu_extension_bridge/Services/LnReader/LnReaderWorker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

void main() {
  LnReaderWorker.clientFactory = () => IOClient(
        HttpClient()..badCertificateCallback = (cert, host, port) => true,
      );
  LnReaderWorker.logSink = (_) {};
  LnReaderWorker.readStore = (_) => null;
  LnReaderWorker.writeStore = (_, __) {};

  test('reproduce segfault with the exact failing order', () async {
    final ids = await File('/tmp/lnreader-test/order.txt').readAsLines();
    for (final id in ids.where((l) => l.trim().isNotEmpty)) {
      // ignore: avoid_print
      print('>>> START $id');
      final file = File('/tmp/lnreader-test/plugins/$id.js');
      final code = await file.readAsString();
      LnReaderWorker? worker;
      try {
        worker = await LnReaderWorker.spawn(sourceId: id, code: code)
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        continue;
      }
      try {
        Map<String, Object?>? popularRes;
        try {
          popularRes = await worker
              .pages('popular', {'page': 1, 'latest': false})
              .timeout(const Duration(seconds: 20));
        } catch (_) {}
        final list = popularRes?['list'] as List?;
        if (list != null && list.isNotEmpty) {
          final first =
              DMedia.fromJson(Map<String, dynamic>.from(list.first as Map));
          try {
            final detail =
                await worker.detail(first).timeout(const Duration(seconds: 20));
            final episodes = detail['episodes'] as List?;
            if (episodes != null && episodes.isNotEmpty) {
              final firstEp = Map<String, dynamic>.from(episodes.first as Map);
              final url = firstEp['url'] as String?;
              if (url != null) {
                try {
                  await worker.content(url).timeout(const Duration(seconds: 20));
                } catch (_) {}
              }
            }
          } catch (_) {}
        }
      } finally {
        try {
          await worker.dispose().timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
