import 'dart:async';
import 'dart:io';

import '../dartotsu_extension_bridge.dart';

enum TestStep { search, detail, units, links }

enum TestStatus { pending, running, passed, failed, skipped }

class StepResult {
  final TestStep step;
  TestStatus status;
  int ms;
  String note;
  String? error;

  StepResult(this.step) : status = TestStatus.pending, ms = 0, note = '';
}

class SourceReport {
  final Source source;
  final steps = [for (final s in TestStep.values) StepResult(s)];

  SourceReport(this.source);

  bool get running => steps.any((s) => s.status == TestStatus.running);

  bool get finished =>
      steps.every((s) => s.status != TestStatus.pending && !running);

  bool get passed => steps.every((s) => s.status == TestStatus.passed);

  StepResult? get firstFailure =>
      steps.where((s) => s.status == TestStatus.failed).firstOrNull;
}

class SourceTester {
  final Duration timeout;
  final bool Function() cancelled;

  SourceTester({
    this.timeout = const Duration(seconds: 30),
    this.cancelled = _never,
  });

  static bool _never() => false;

  Future<void> run(
    SourceReport report,
    ItemType type,
    String query,
    void Function() changed,
  ) async {
    for (final s in report.steps) {
      s
        ..status = TestStatus.pending
        ..ms = 0
        ..note = ''
        ..error = null;
    }
    changed();
    final methods = report.source.methods;
    DMedia? hit;
    DMedia? detail;
    DEpisode? unit;

    hit = await _step<DMedia>(report, TestStep.search, changed, () async {
      final pages = await methods.search(query, 1, const []);
      final list = pages.list.where((m) => m.url?.isNotEmpty ?? false).toList();
      if (list.isEmpty) {
        throw TestFailure(
          pages.list.isEmpty
              ? 'No results for "$query"'
              : 'Results have no url (${pages.list.length} items)',
        );
      }
      final noTitle = list.where((m) => (m.title ?? '').trim().isEmpty).length;
      return (
        list.first,
        '${list.length} results${noTitle > 0 ? ', $noTitle without a title' : ''} · "${list.first.title}"',
      );
    });

    final foundDetail = hit;
    detail = await _step<DMedia>(
      report,
      TestStep.detail,
      changed,
      foundDetail == null
          ? null
          : () async {
              final d = await methods.getDetail(foundDetail);
              return (
                d,
                [
                  if ((d.title ?? '').isNotEmpty) d.title!,
                  if ((d.description ?? '').isNotEmpty) 'description',
                  if ((d.cover ?? '').isNotEmpty) 'cover',
                ].join(' · '),
              );
            },
      skipReason: 'search failed',
    );

    final withDetail = detail;
    unit = await _step<DEpisode>(
      report,
      TestStep.units,
      changed,
      withDetail == null
          ? null
          : () async {
              final list = withDetail.episodes ?? const <DEpisode>[];
              if (list.isEmpty) {
                throw TestFailure(
                  'getDetail returned no ${type == ItemType.anime ? 'episodes' : 'chapters'}',
                );
              }
              final missing = list.where((e) => e.url?.isNotEmpty != true);
              if (missing.length == list.length) {
                throw TestFailure('Every entry is missing its url');
              }
              final first = list.firstWhere((e) => e.url?.isNotEmpty ?? false);
              return (
                first,
                '${list.length} found${missing.isEmpty ? '' : ', ${missing.length} without a url'}',
              );
            },
      skipReason: 'details failed',
    );

    final target = unit;
    await _step<void>(
      report,
      TestStep.links,
      changed,
      target == null
          ? null
          : () async {
              final note = switch (type) {
                ItemType.anime => await _videos(methods, target),
                ItemType.manga => await _pages(methods, target),
                ItemType.novel => await _novel(methods, target),
              };
              return (null, note);
            },
      skipReason: 'no entries to open',
      limit: timeout * 2,
    );
  }

  Future<String> _videos(SourceMethods methods, DEpisode unit) async {
    final list = await methods.getVideoList(unit);
    if (list.isEmpty) throw TestFailure('No streams returned');
    final bad = list.where((v) => v.url.isEmpty || v.url == 'null');
    if (bad.length == list.length) throw TestFailure('Streams have no url');
    final first = list.firstWhere((v) => v.url.isNotEmpty);
    final probe = await _probe(first.url, first.headers);
    return '${list.length} streams · ${first.quality.isEmpty ? 'unnamed' : first.quality} · $probe';
  }

  Future<String> _pages(SourceMethods methods, DEpisode unit) async {
    final list = await methods.getPageList(unit);
    if (list.isEmpty) throw TestFailure('No pages returned');
    final probe = await _probe(list.first.url, list.first.headers);
    return '${list.length} pages · $probe';
  }

  Future<String> _novel(SourceMethods methods, DEpisode unit) async {
    final text = await methods.getNovelContent(unit);
    if (text == null || text.trim().isEmpty) {
      throw TestFailure('Chapter text is empty');
    }
    return '${text.length} characters';
  }

  Future<String> _probe(String url, Map<String, String>? headers) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      if (url.startsWith('/') || url.startsWith('file:')) return 'local file';
      throw TestFailure('Not a valid link: $url');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return uri.scheme;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      headers?.forEach(request.headers.set);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      await response.drain<void>();
      final code = response.statusCode;
      if (code >= 400) {
        throw TestFailure('Link answered HTTP $code (${uri.host})');
      }
      return 'link reachable (HTTP $code)';
    } on TimeoutException {
      throw TestFailure('Link did not answer in time (${uri.host})');
    } on SocketException catch (e) {
      throw TestFailure('Link unreachable: ${e.message} (${uri.host})');
    } on HandshakeException catch (e) {
      throw TestFailure('TLS error on ${uri.host}: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<T?> _step<T>(
    SourceReport report,
    TestStep step,
    void Function() changed,
    Future<(T?, String)> Function()? body, {
    String skipReason = '',
    Duration? limit,
  }) async {
    final result = report.steps.firstWhere((s) => s.step == step);
    if (body == null || cancelled()) {
      result
        ..status = TestStatus.skipped
        ..note = cancelled() ? 'stopped' : skipReason;
      changed();
      return null;
    }
    result.status = TestStatus.running;
    changed();
    final clock = Stopwatch()..start();
    try {
      final (value, note) = await body().timeout(limit ?? timeout);
      result
        ..status = TestStatus.passed
        ..note = note;
      return value;
    } on TimeoutException {
      result
        ..status = TestStatus.failed
        ..error = 'Timed out after ${(limit ?? timeout).inSeconds} s';
    } on TestFailure catch (e) {
      result
        ..status = TestStatus.failed
        ..error = e.message;
    } catch (e, st) {
      result
        ..status = TestStatus.failed
        ..error = '$e\n${_trace(st)}';
    } finally {
      result.ms = clock.elapsedMilliseconds;
      changed();
    }
    return null;
  }

  String _trace(StackTrace st) =>
      st.toString().split('\n').take(4).join('\n').trim();
}

class TestFailure implements Exception {
  final String message;
  TestFailure(this.message);

  @override
  String toString() => message;
}

String reportText(Iterable<SourceReport> reports, ItemType type) {
  final buffer = StringBuffer('Extension test (${type.name})\n');
  for (final r in reports) {
    final fail = r.firstFailure;
    buffer.writeln(
      '\n${r.source.name} [${r.source.lang ?? '?'}] — ${fail == null ? (r.passed ? 'ok' : 'incomplete') : 'failed at ${fail.step.name}'}',
    );
    for (final s in r.steps) {
      buffer.writeln(
        '  ${s.step.name}: ${s.status.name}'
        '${s.ms > 0 ? ' (${s.ms} ms)' : ''}'
        '${s.note.isNotEmpty ? ' — ${s.note}' : ''}'
        '${s.error != null ? '\n    ${s.error!.replaceAll('\n', '\n    ')}' : ''}',
      );
    }
  }
  return buffer.toString();
}

final _failureLine = RegExp(
  r'×|error|failed|exception|timed out|← [45]\d\d|cloudflare|flaresolverr|call failed|NoSuchMethod',
  caseSensitive: false,
);

String _clip(String message, int max) =>
    message.length <= max ? message : '${message.substring(0, max)}…';

String failureLogs(List<String> messages, {int max = 800}) {
  final kept = [
    for (final m in messages)
      if (_failureLine.hasMatch(m)) _clip(m.trimRight(), 1200),
  ];
  final shown = kept.length > max ? kept.sublist(kept.length - max) : kept;
  return shown.join('\n');
}

String allLogs(List<String> messages) =>
    messages.map((m) => _clip(m.trimRight(), 2000)).join('\n');
