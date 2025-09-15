import '../string_extensions.dart';
import 'package:http_interceptor/http_interceptor.dart';

import '../Eval/dart/model/video.dart';
import '../http/m_client.dart';

class StreamWishExtractor {
  final InterceptedClient client = MClient.init(
    reqcopyWith: {'useDartHttpClient': true},
  );
  final Map<String, String> headers = {};

  Future<List<Video>> videosFromUrl(String url, String prefix) async {
    final videoList = <Video>[];
    try {
      final response = await client.get(Uri.parse(url), headers: headers);
      final body = response.body;

      final RegExp scriptTagRe =
          RegExp(r'<script[^>]*>([\s\S]*?)<\/script>', multiLine: true);
      String? scriptContent;
      for (final m in scriptTagRe.allMatches(body)) {
        final inner = m.group(1);
        if (inner != null && inner.contains('m3u8')) {
          scriptContent = inner;
          break;
        }
      }
      if (scriptContent == null) return [];

      final String unpacked = scriptContent;

      String? masterUrl;
      if (unpacked.contains('source') && unpacked.contains('file:"')) {
        masterUrl = unpacked
            .substringAfter('source')
            .substringAfter('file:"')
            .substringBefore('"');
      }
      if (masterUrl == null || masterUrl.isEmpty) return [];

      final playlistHeaders = Map<String, String>.from(headers)
        ..addAll({
          'Accept': '*/*',
          'Host': Uri.parse(masterUrl).host,
          'Origin': 'https://${Uri.parse(url).host}',
          'Referer': 'https://${Uri.parse(url).host}/',
        });

      final masterBase =
          '${'https://${Uri.parse(masterUrl).host}${Uri.parse(masterUrl).path}'.substringBeforeLast('/')}/';

      final masterPlaylistResponse = await client.get(Uri.parse(masterUrl), headers: playlistHeaders);
      final masterPlaylist = masterPlaylistResponse.body;

      const separator = '#EXT-X-STREAM-INF:';
      masterPlaylist.substringAfter(separator).split(separator).forEach((it) {
        final quality =
            '$prefix - ${it.substringAfter('RESOLUTION=').substringAfter('x').substringBefore(',')}p ';
        final videoUrl =
            masterBase + it.substringAfter('\n').substringBefore('\n');
        videoList.add(Video(videoUrl, quality, videoUrl, headers: playlistHeaders));
      });

      return videoList;
    } catch (_) {
      return [];
    }
  }
}