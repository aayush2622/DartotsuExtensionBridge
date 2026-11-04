import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../Engines/Ffmpeg/FfmpegAddon.dart';
import '../Logger.dart';
import '../Toolkit/Dash.dart';
import 'DownloadCancel.dart';
import 'FileFetcher.dart';
import 'HlsDownload.dart';
import 'HttpStream.dart';

const _fileUnits = 100;

bool isDashResponse(String? contentType, List<int> head) {
  if ((contentType ?? '').toLowerCase().contains('dash+xml')) return true;
  return isDashManifest(utf8.decode(head, allowMalformed: true));
}

Future<bool> probeDash(String url, {Map<String, String>? headers}) async {
  try {
    final res = await openStream(
      url,
      headers: {...?headers, 'Range': 'bytes=0-2047'},
    );
    if (res.statusCode >= 400) {
      await res.drop();
      return false;
    }
    final type = res.headers['content-type'];
    if ((type ?? '').toLowerCase().contains('dash+xml')) {
      await res.drop();
      return true;
    }
    final head = <int>[];
    await for (final chunk in res.body.timeout(const Duration(seconds: 20))) {
      head.addAll(chunk);
      if (head.length >= 2048) break;
    }
    return isDashResponse(type, head);
  } catch (_) {
    return false;
  }
}

Future<DashManifest> loadDash(
  String url, {
  Map<String, String>? headers,
}) async => parseMpd(await fetchText(url, headers: headers), Uri.parse(url));

Future<void> downloadDash({
  required String url,
  required File output,
  required FfmpegAddon? ffmpeg,
  required DownloadCancel cancel,
  required FfmpegCancel ffmpegCancel,
  required void Function(int done, int total) onProgress,
  required void Function() onFinishing,
  Map<String, String>? headers,
  int? height,
  List<String> audioLabels = const [],
  int workers = 4,
  Future<String> Function(String url)? getText,
  Future<void> Function(Uri uri, File target)? getFile,
}) async {
  final text =
      await (getText?.call(url) ??
          fetchText(url, headers: headers, cancel: cancel));
  final manifest = parseMpd(text, Uri.parse(url));
  if (manifest.protected) {
    throw const DashUnsupported('This stream is DRM protected');
  }
  if (manifest.videos.isEmpty) {
    throw const DashUnsupported('The DASH manifest has no video');
  }
  final video = pickDashVideo(manifest.videos, height: height);
  final audios = video.isMuxed
      ? const <DashRepresentation>[]
      : pickDashAudios(manifest.audios, audioLabels);
  final reps = [video, ...audios];
  if (audios.isNotEmpty && ffmpeg == null) {
    throw const DashUnsupported(
      'FFmpeg is required to merge the audio track',
      needsFfmpeg: true,
    );
  }

  final name = p.basenameWithoutExtension(output.path);
  final work = Directory(p.join(output.parent.path, '.$name'));
  await work.create(recursive: true);

  var total = 0;
  for (final r in reps) {
    total += r.file != null
        ? _fileUnits
        : r.segments.length + (r.init != null ? 1 : 0);
  }
  var done = 0;
  var partial = 0;
  void report() => onProgress(done + partial, total);

  Future<void> grab(Uri uri, File target, {bool single = false}) async {
    if (await target.exists() && await target.length() > 0) return;
    if (getFile != null) return getFile(uri, target);
    await fetchWithRetry(
      () => fetchFile(
        url: uri.toString(),
        target: target,
        cancel: cancel,
        headers: headers,
        onProgress: (received, size) {
          if (!single || size <= 0) return;
          partial = (_fileUnits * received / size).floor().clamp(
            0,
            _fileUnits - 1,
          );
          report();
        },
      ),
      cancel: cancel,
    );
  }

  report();
  final merged = <File>[];
  for (final (index, rep) in reps.indexed) {
    final dir = Directory(p.join(work.path, 'rep$index'));
    await dir.create(recursive: true);
    final joined = File(p.join(work.path, 'rep$index.mp4'));
    if (rep.file != null) {
      final target = File(p.join(dir.path, 'file.mp4'));
      await grab(rep.file!, target, single: true);
      partial = 0;
      done += _fileUnits;
      report();
      merged.add(target);
      continue;
    }
    final parts = <File>[];
    final init = rep.init;
    if (init != null) {
      final file = File(p.join(dir.path, 'init.mp4'));
      await grab(init, file);
      parts.add(file);
      done++;
      report();
    }
    Object? failure;
    var next = 0;
    final files = [
      for (final (i, _) in rep.segments.indexed)
        File(p.join(dir.path, 'seg${(i + 1).toString().padLeft(6, '0')}.m4s')),
    ];
    Future<void> worker() async {
      while (failure == null) {
        final n = next++;
        if (n >= rep.segments.length) return;
        try {
          await grab(rep.segments[n], files[n]);
          done++;
          report();
        } catch (e) {
          Logger.log('DASH segment ${n + 1}/${rep.segments.length} failed: $e');
          failure ??= e;
        }
      }
    }

    await Future.wait([for (var k = 0; k < workers; k++) worker()]);
    final error = failure;
    if (error != null) throw error;
    parts.addAll(files);
    if (await joined.exists()) await joined.delete();
    final sink = joined.openWrite();
    try {
      for (final part in parts) {
        await sink.addStream(part.openRead());
      }
    } finally {
      await sink.close();
    }
    merged.add(joined);
  }

  final temp = File('${output.path}.part.mp4');
  if (await temp.exists()) await temp.delete();
  if (ffmpeg == null) {
    await merged.first.copy(temp.path);
  } else {
    onFinishing();
    await ffmpeg.run([
      for (final file in merged) ...['-i', file.path],
      if (audios.isEmpty) ...[
        '-map',
        '0',
      ] else ...[
        '-map',
        '0:v:0',
        for (var i = 0; i < audios.length; i++) ...['-map', '${i + 1}:a:0'],
        for (final (i, a) in audios.indexed) ...[
          '-metadata:s:a:$i',
          'title=${a.audioLabel}',
          if ((a.language ?? '').isNotEmpty) ...[
            '-metadata:s:a:$i',
            'language=${a.language}',
          ],
        ],
      ],
      '-c',
      'copy',
      '-movflags',
      '+faststart',
      temp.path,
    ], cancel: ffmpegCancel);
  }
  if (await output.exists()) await output.delete();
  await temp.rename(output.path);
  await work.delete(recursive: true);
  onProgress(total, total);
}
