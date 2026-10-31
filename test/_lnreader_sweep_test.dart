import 'dart:async';
import 'dart:convert';
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

  test('sweep every LNReader plugin', () async {
    final dir = Directory('/tmp/lnreader-test/plugins');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.js'))
        .toList();
    print('plugins: ${files.length}');

    final results = <String, Map<String, Object?>>{};
    final sem = _Semaphore(1);

    Future<void> runOne(File file) async {
      final id = file.uri.pathSegments.last.replaceAll('.js', '');
      final entry = <String, Object?>{};
      results[id] = entry;
      await sem.acquire();
      // ignore: avoid_print
      print('>>> START $id');
      try {
        final code = await file.readAsString();
        LnReaderWorker? worker;
        try {
          worker = await LnReaderWorker.spawn(sourceId: id, code: code)
              .timeout(const Duration(seconds: 15));
        } catch (e) {
          entry['spawnError'] = '$e';
          return;
        }
        try {
          Map<String, Object?>? popularRes;
          try {
            popularRes = await worker
                .pages('popular', {'page': 1, 'latest': false})
                .timeout(const Duration(seconds: 25));
            entry['popularOk'] = true;
            entry['popularCount'] = (popularRes['list'] as List?)?.length;
          } catch (e) {
            entry['popularError'] = '$e';
          }

          final list = popularRes?['list'] as List?;
          if (list != null && list.isNotEmpty) {
            final first = DMedia.fromJson(Map<String, dynamic>.from(list.first as Map));
            try {
              final detail = await worker.detail(first).timeout(const Duration(seconds: 25));
              entry['detailOk'] = true;
              final episodes = detail['episodes'] as List?;
              entry['chapterCount'] = episodes?.length;
              if (episodes != null && episodes.isNotEmpty) {
                final firstEp = Map<String, dynamic>.from(episodes.first as Map);
                final url = firstEp['url'] as String?;
                if (url != null) {
                  try {
                    final content = await worker.content(url).timeout(const Duration(seconds: 25));
                    entry['contentOk'] = content != null && content.trim().isNotEmpty;
                    entry['contentLen'] = content?.length;
                  } catch (e) {
                    entry['contentError'] = '$e';
                  }
                }
              }
            } catch (e) {
              entry['detailError'] = '$e';
            }
          }
        } finally {
          try {
            await worker.dispose().timeout(const Duration(seconds: 5));
          } catch (_) {}
        }
      } finally {
        sem.release();
      }
    }

    await Future.wait(files.map(runOne));

    final out = File('/tmp/lnreader-test/results.json');
    out.writeAsStringSync(jsonEncode(results));

    final popularOk = results.values.where((e) => e['popularOk'] == true).length;
    final detailOk = results.values.where((e) => e['detailOk'] == true).length;
    final contentOk = results.values.where((e) => e['contentOk'] == true).length;
    print('popularOk=$popularOk detailOk=$detailOk contentOk=$contentOk total=${results.length}');
  }, timeout: const Timeout(Duration(minutes: 20)));
}

class _Semaphore {
  _Semaphore(this._max);
  final int _max;
  int _current = 0;
  final _waiters = <Completer<void>>[];

  Future<void> acquire() {
    if (_current < _max) {
      _current++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void release() {
    _current--;
    if (_waiters.isNotEmpty) {
      _current++;
      final c = _waiters.removeAt(0);
      c.complete();
    }
  }
}
