import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'DownloadCancel.dart';
import 'HttpStream.dart';
import 'Throttle.dart';

typedef DownloadHttpError = HttpStatusError;

class _HostPace {
  Duration gap = _baseGap;
  DateTime until = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime last = DateTime.fromMillisecondsSinceEpoch(0);
}

const _baseGap = Duration(milliseconds: 150);
final _paces = <String, _HostPace>{};

_HostPace _paceOf(String url) =>
    _paces.putIfAbsent(Uri.tryParse(url)?.host ?? url, _HostPace.new);

Future<void> _pace(String url) async {
  final pace = _paceOf(url);
  final now = DateTime.now();
  var start = pace.last.add(pace.gap);
  if (pace.until.isAfter(start)) start = pace.until;
  if (start.isBefore(now)) start = now;
  pace.last = start;
  final wait = start.difference(now);
  if (wait > Duration.zero) await Future<void>.delayed(wait);
}

void _penalize(String url, Duration? retryAfter) {
  final pace = _paceOf(url);
  final doubled = pace.gap * 2;
  pace.gap = doubled > const Duration(seconds: 4)
      ? const Duration(seconds: 4)
      : doubled;
  final hold = retryAfter ?? const Duration(seconds: 6);
  final until = DateTime.now().add(hold);
  if (until.isAfter(pace.until)) pace.until = until;
}

void _relax(String url) {
  final pace = _paceOf(url);
  final shrunk = Duration(
    milliseconds: (pace.gap.inMilliseconds * 0.9).round(),
  );
  pace.gap = shrunk < _baseGap ? _baseGap : shrunk;
}

Duration? _retryAfter(FetchResponse res) {
  final seconds = int.tryParse(res.headers['retry-after'] ?? '');
  return seconds == null ? null : Duration(seconds: seconds.clamp(1, 120));
}

int? _totalOf(FetchResponse res, int offset) {
  final range = res.headers['content-range'];
  if (range != null) {
    final total = int.tryParse(range.split('/').last.trim());
    if (total != null) return total;
  }
  final length = int.tryParse(res.headers['content-length'] ?? '');
  return length == null ? null : length + offset;
}

bool _retryable(Object e) {
  if (e is DownloadHttpError) return e.status == 429 || e.status >= 500;
  return e is SocketException || e is HttpException || e is TimeoutException;
}

Future<void> fetchWithRetry(
  Future<void> Function() run, {
  required DownloadCancel cancel,
  int attempts = 10,
}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await run();
    } catch (e) {
      if (cancel.isCancelled || attempt >= attempts || !_retryable(e)) rethrow;
      final wait = e is DownloadHttpError && e.status == 429
          ? (e.retryAfter ?? Duration(seconds: (3 * attempt).clamp(3, 30)))
          : Duration(seconds: attempt * attempt);
      await Future<void>.delayed(wait);
    }
  }
}

const _chunkedMinimum = 8 * 1024 * 1024;
const _idle = Duration(seconds: 60);

Future<bool> _fetchChunked({
  required String url,
  required File target,
  required DownloadCancel cancel,
  required void Function(int received, int total) onProgress,
  required int connections,
  Map<String, String>? headers,
}) async {
  final part = File('${target.path}.part');
  final map = File('${part.path}.map');
  await part.parent.create(recursive: true);
  int total;
  List<List<int>> ranges;
  if (await map.exists() && await part.exists()) {
    try {
      final json = jsonDecode(await map.readAsString()) as Map;
      total = json['total'] as int;
      ranges = [
        for (final r in json['ranges'] as List)
          [for (final v in r as List) (v as num).toInt()],
      ];
    } catch (_) {
      await map.delete();
      return false;
    }
  } else {
    if (await part.exists() && await part.length() > 0) {
      return false;
    }
    final probe = await openStream(
      url,
      headers: {...?headers, 'Range': 'bytes=0-0'},
      cancel: cancel,
    );
    final size = probe.statusCode == 206
        ? int.tryParse((probe.headers['content-range'] ?? '').split('/').last)
        : null;
    await probe.drop();
    if (size == null || size < _chunkedMinimum) return false;
    total = size;
    final count = connections.clamp(1, total ~/ _chunkedMinimum).toInt();
    final step = (total / count).ceil();
    ranges = [
      for (var i = 0; i < count; i++)
        [i * step, (i + 1) * step < total ? (i + 1) * step - 1 : total - 1, 0],
    ];
    final create = await part.open(mode: FileMode.write);
    await create.truncate(total);
    await create.close();
  }

  Future<void> save() =>
      map.writeAsString(jsonEncode({'total': total, 'ranges': ranges}));

  int received() => ranges.fold(0, (sum, r) => sum + r[2]);

  var failed = false;
  Object? failure;
  var lastSave = DateTime.now();

  Future<void> worker(List<int> range) async {
    final length = range[1] - range[0] + 1;
    if (range[2] >= length) return;
    final file = await part.open(mode: FileMode.append);
    try {
      final res = await openStream(
        url,
        headers: {
          ...?headers,
          'Range': 'bytes=${range[0] + range[2]}-${range[1]}',
        },
        cancel: cancel,
      );
      if (res.statusCode != 206) {
        await res.drop();
        throw DownloadHttpError(res.statusCode);
      }
      await for (final chunk in res.body.timeout(_idle)) {
        if (failed) return;
        final room = length - range[2];
        final data = chunk.length > room ? chunk.sublist(0, room) : chunk;
        await file.setPosition(range[0] + range[2]);
        await file.writeFrom(data);
        range[2] += data.length;
        onProgress(received(), total);
        await DownloadThrottle.take(data.length);
        if (DateTime.now().difference(lastSave).inSeconds >= 1) {
          lastSave = DateTime.now();
          unawaited(save());
        }
        if (range[2] >= length) return;
      }
    } catch (e) {
      failed = true;
      failure ??= e;
    } finally {
      await file.close();
    }
  }

  await save();
  await Future.wait([for (final r in ranges) worker(r)]);
  await save();
  final error = failure;
  if (error != null) throw error;
  if (received() < total) {
    throw const SocketException('Connection closed early');
  }
  if (await target.exists()) await target.delete();
  await part.rename(target.path);
  await map.delete();
  return true;
}

Future<void> fetchFile({
  required String url,
  required File target,
  required DownloadCancel cancel,
  required void Function(int received, int total) onProgress,
  Map<String, String>? headers,
  int connections = 1,
}) async {
  if (connections > 1 &&
      await _fetchChunked(
        url: url,
        target: target,
        cancel: cancel,
        onProgress: onProgress,
        connections: connections,
        headers: headers,
      )) {
    return;
  }
  final part = File('${target.path}.part');
  await part.parent.create(recursive: true);
  final have = await part.exists() ? await part.length() : 0;
  final sent = {...?headers, if (have > 0) 'Range': 'bytes=$have-'};
  await _pace(url);
  final res = await openStream(url, headers: sent, cancel: cancel);
  if (res.statusCode == 416 && have > 0) {
    await part.rename(target.path);
    return;
  }
  if (res.statusCode == 429) {
    final after = _retryAfter(res);
    _penalize(url, after);
    await res.drop();
    throw DownloadHttpError(429, retryAfter: after);
  }
  if (res.statusCode >= 400) {
    await res.drop();
    throw DownloadHttpError(res.statusCode);
  }
  _relax(url);
  final resumed = have > 0 && res.statusCode == 206;
  var received = resumed ? have : 0;
  final total = _totalOf(res, resumed ? have : 0) ?? -1;
  final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
  try {
    await for (final chunk in res.body.timeout(_idle)) {
      sink.add(chunk);
      received += chunk.length;
      onProgress(received, total);
      await DownloadThrottle.take(chunk.length);
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  if (total > 0 && received < total) {
    throw const SocketException('Connection closed early');
  }
  if (await target.exists()) await target.delete();
  await part.rename(target.path);
}
