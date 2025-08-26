import 'dart:convert';
import 'package:http_interceptor/http_interceptor.dart';

import '../Eval/dart/model/video.dart';
import '../http/m_client.dart';
import '../string_extensions.dart';

class FilemoonExtractor {
  final InterceptedClient client = MClient.init(
    reqcopyWith: {'useDartHttpClient': true},
  );

  Future<List<Video>> videosFromUrl(
    String url,
    String prefix,
    String suffix,
  ) async {
    prefix = prefix.isEmpty ? "Filemoon " : prefix;
    try {
      final videoHeaders = {
        'Referer': url,
        'Origin': 'https://${Uri.parse(url).host}',
      };
      final response = await client.get(Uri.parse(url));

      final body = response.body;

      final RegExp scriptTagRe = RegExp(
        r'<script[^>]*>([\s\S]*?)<\/script>',
        multiLine: true,
      );
      String? jsEval;
      for (final m in scriptTagRe.allMatches(body)) {
        final inner = m.group(1);
        if (inner != null && inner.contains('eval')) {
          jsEval = inner;
          break;
        }
      }

      if (jsEval == null) return [];

      final String unpacked =
          jsEval;

      final masterUrl = unpacked.isNotEmpty
          ? unpacked.substringAfter('{file:"').substringBefore('"}')
          : '';

      if (masterUrl.isEmpty) {
        return [];
      }

      List<Track> subtitleTracks = [];
      final subUrl =
          Uri.parse(url).queryParameters["sub.info"] ??
          unpacked.substringAfter("""fetch('", """).substringBefore("""').""");
      if (subUrl.isNotEmpty) {
        try {
          final subResponse = await client.get(
            Uri.parse(subUrl),
            headers: videoHeaders,
          );
          final subList = jsonDecode(subResponse.body) as List;
          for (var item in subList) {
            subtitleTracks.add(Track(file: item["file"], label: item["label"]));
          }
        } catch (_) {}
      }

      final masterPlaylistResponse = await client.get(Uri.parse(masterUrl));
      final masterPlaylist = masterPlaylistResponse.body;

      const separator = '#EXT-X-STREAM-INF:';
      final playlists = masterPlaylist.split(separator).sublist(1);

      return playlists.map((playlist) {
        final resolution =
            '${playlist.substringAfter('RESOLUTION=').substringAfter('x').substringBefore(',').trim()}p';
        final videoUrl = playlist.split('\n')[1].trim();

        return Video(
          videoUrl,
          "$prefix - $resolution $suffix",
          videoUrl,
          headers: videoHeaders,
          subtitles: subtitleTracks,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
