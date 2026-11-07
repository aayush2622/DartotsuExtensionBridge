import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../Engines/Ffmpeg/FfmpegAddon.dart';
import '../Logger.dart';
import '../Toolkit/Hls.dart';
import 'DownloadCancel.dart';
import 'FileFetcher.dart';
import 'HttpStream.dart';

Future<bool> _complete(File file) async =>
    await file.exists() && await file.length() > 0;

Future<String> fetchText(
  String url, {
  Map<String, String>? headers,
  DownloadCancel? cancel,
}) => readText(url, headers: headers, cancel: cancel);

bool isHlsResponse(String? contentType, List<int> head) {
  if ((contentType ?? '').toLowerCase().contains('mpegurl')) return true;
  final text = utf8
      .decode(head, allowMalformed: true)
      .replaceFirst('\uFEFF', '')
      .trimLeft();
  return text.startsWith('#EXTM3U');
}

Future<bool> probeHls(String url, {Map<String, String>? headers}) async {
  try {
    final res = await openStream(
      url,
      headers: {...?headers, 'Range': 'bytes=0-255'},
    );
    if (res.statusCode >= 400) {
      await res.drop();
      return false;
    }
    final type = res.headers['content-type'];
    if ((type ?? '').toLowerCase().contains('mpegurl')) {
      await res.drop();
      return true;
    }
    final head = <int>[];
    await for (final chunk in res.body.timeout(const Duration(seconds: 20))) {
      head.addAll(chunk);
      if (head.length >= 256) break;
    }
    return isHlsResponse(type, head);
  } catch (_) {
    return false;
  }
}

class HlsMaster {
  final List<HlsVariant> variants;
  final List<HlsAudio> audios;

  const HlsMaster(this.variants, this.audios);
}

Future<HlsMaster> loadMaster(String url, {Map<String, String>? headers}) async {
  final text = await fetchText(url, headers: headers);
  if (!isMasterPlaylist(text)) return const HlsMaster([], []);
  final base = Uri.parse(url);
  return HlsMaster(parseMaster(text, base), parseAudios(text, base));
}

Future<List<HlsVariant>> loadVariants(
  String url, {
  Map<String, String>? headers,
}) async => (await loadMaster(url, headers: headers)).variants;

Future<void> downloadHls({
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
  List<String> audioUrls = const [],
  int workers = 4,
  Future<String> Function(String url)? getText,
  Future<void> Function(Uri uri, File target)? getFile,
}) async {
  Future<String> text0(String u) =>
      getText?.call(u) ?? fetchText(u, headers: headers, cancel: cancel);
  var playlistUrl = url;
  var text = await text0(url);
  var audios = <HlsAudio>[];
  if (isMasterPlaylist(text)) {
    final base = Uri.parse(url);
    final variants = parseMaster(text, base);
    if (variants.isEmpty) throw const HlsUnsupported('Empty master playlist');
    final variant = pickVariant(variants, height: height);
    playlistUrl = variant.uri.toString();
    audios = pickAudios(parseAudios(text, base), variant, audioLabels);
    text = await text0(playlistUrl);
  } else {
    for (final (i, audioUrl) in audioUrls.indexed) {
      if (audioUrl.isEmpty) continue;
      audios.add(
        HlsAudio(
          Uri.parse(audioUrl),
          i < audioLabels.length ? audioLabels[i] : '',
          null,
          'audio',
          i == 0,
        ),
      );
    }
  }
  final media = parseMedia(text, Uri.parse(playlistUrl));
  final audioMedias = [
    for (final audio in audios)
      parseMedia(await text0(audio.uri.toString()), audio.uri!),
  ];
  final name = p.basenameWithoutExtension(output.path);
  final dir = Directory(
    p.join(output.parent.path, ffmpeg == null ? name : '.$name'),
  );
  await dir.create(recursive: true);
  final audioDirs = [
    for (var i = 0; i < audioMedias.length; i++)
      Directory(
        p.join(dir.path, audioMedias.length == 1 ? 'audio' : 'audio$i'),
      ),
  ];
  for (final audioDir in audioDirs) {
    await audioDir.create(recursive: true);
  }

  Future<void> grab(Directory into, Uri uri, String name) async {
    final target = File(p.join(into.path, name));
    if (await _complete(target)) return;
    if (getFile != null) return getFile(uri, target);
    await fetchWithRetry(
      () => fetchFile(
        url: uri.toString(),
        target: target,
        cancel: cancel,
        headers: headers,
        onProgress: (_, _) {},
      ),
      cancel: cancel,
    );
  }

  final total =
      media.segments.length +
      audioMedias.fold<int>(0, (sum, m) => sum + m.segments.length);
  var done = 0;
  Object? failure;

  Future<({Map<Uri, String> keys, Map<Uri, String> maps})> pull(
    HlsMedia item,
    Directory into,
  ) async {
    final keys = <Uri, String>{};
    final maps = <Uri, String>{};
    for (final s in item.segments) {
      final key = s.key?.uri;
      if (key != null) keys.putIfAbsent(key, () => 'key${keys.length}.ts');
      final map = s.map;
      if (map != null) {
        maps.putIfAbsent(
          map,
          () => 'init${maps.length}.${hlsExtension(map, fallback: 'mp4')}',
        );
      }
    }
    for (final e in keys.entries) {
      await grab(into, e.key, e.value);
    }
    for (final e in maps.entries) {
      await grab(into, e.key, e.value);
    }
    final pending = <int>[];
    for (final (i, s) in item.segments.indexed) {
      if (await _complete(File(p.join(into.path, segmentName(i, s.uri))))) {
        done++;
      } else {
        pending.add(i);
      }
    }
    onProgress(done, total);
    var next = 0;
    Future<void> worker() async {
      while (failure == null) {
        final n = next++;
        if (n >= pending.length) return;
        final i = pending[n];
        try {
          final uri = item.segments[i].uri;
          await grab(into, uri, segmentName(i, uri));
          done++;
          onProgress(done, total);
        } catch (e) {
          Logger.log('HLS segment ${i + 1}/${item.segments.length} failed: $e');
          failure ??= e;
        }
      }
    }

    await Future.wait([for (var k = 0; k < workers; k++) worker()]);
    final error = failure;
    if (error != null) throw error;
    return (keys: keys, maps: maps);
  }

  Future<void> writePlaylist(
    HlsMedia item,
    File target,
    ({Map<Uri, String> keys, Map<Uri, String> maps}) names,
  ) => target.writeAsString(
    buildLocalPlaylist(
      item,
      keyName: (uri) => names.keys[uri]!,
      mapName: (uri) => names.maps[uri]!,
    ),
  );

  final videoNames = await pull(media, dir);
  final audioNames = [
    for (final (i, m) in audioMedias.indexed) await pull(m, audioDirs[i]),
  ];

  final videoPlaylist = File(
    p.join(
      dir.path,
      ffmpeg != null
          ? 'local.m3u8'
          : (audioMedias.isEmpty ? 'index.m3u8' : 'video.m3u8'),
    ),
  );
  await writePlaylist(media, videoPlaylist, videoNames);
  final audioPlaylists = <File>[];
  for (final (i, m) in audioMedias.indexed) {
    final file = File(
      p.join(audioDirs[i].path, ffmpeg != null ? 'local.m3u8' : 'audio.m3u8'),
    );
    await writePlaylist(m, file, audioNames[i]);
    audioPlaylists.add(file);
  }
  if (ffmpeg == null) {
    if (audios.isNotEmpty) {
      await File(p.join(dir.path, 'index.m3u8')).writeAsString(
        buildLocalMaster(
          audios: [
            for (final (i, audio) in audios.indexed)
              (audio, '${p.basename(audioDirs[i].path)}/audio.m3u8'),
          ],
          videoPath: 'video.m3u8',
        ),
      );
    }
    return;
  }
  onFinishing();
  final temp = File('${output.path}.part.mp4');
  if (await temp.exists()) await temp.delete();
  if (audioPlaylists.isEmpty) {
    await ffmpeg.remuxPlaylist(
      playlist: videoPlaylist.path,
      output: temp.path,
      cancel: ffmpegCancel,
    );
  } else {
    const input = [
      '-allowed_extensions',
      'ALL',
      '-protocol_whitelist',
      'file,crypto,data',
      '-i',
    ];
    await ffmpeg.run([
      ...input,
      videoPlaylist.path,
      for (final file in audioPlaylists) ...[...input, file.path],
      '-map',
      '0:v:0',
      for (var i = 0; i < audioPlaylists.length; i++) ...[
        '-map',
        '${i + 1}:a:0',
      ],
      for (final (i, audio) in audios.indexed) ...[
        '-metadata:s:a:$i',
        'title=${audio.label}',
        if (audio.language != null && audio.language!.isNotEmpty) ...[
          '-metadata:s:a:$i',
          'language=${audio.language}',
        ],
      ],
      '-c',
      'copy',
      '-bsf:a',
      'aac_adtstoasc',
      '-movflags',
      '+faststart',
      temp.path,
    ], cancel: ffmpegCancel);
  }
  if (await output.exists()) await output.delete();
  await temp.rename(output.path);
  await dir.delete(recursive: true);
}
