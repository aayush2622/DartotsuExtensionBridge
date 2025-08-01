import '../string_extensions.dart';
import 'package:html/parser.dart' as parser;
import 'package:http_interceptor/http_interceptor.dart';

import '../Eval/dart/model/video.dart';
import '../http/m_client.dart';

class SendvidExtractor {
  final InterceptedClient client = MClient.init(
    reqcopyWith: {'useDartHttpClient': true},
  );
  final Map<String, String> headers;

  SendvidExtractor(this.headers);

  Future<List<Video>> videosFromUrl(String url, {String prefix = ""}) async {
    try {
      final videoList = <Video>[];
      final response = await client.get(Uri.parse(url));
      final document = parser.parse(response.body);
      final masterUrl =
      document.querySelector("source#video_source")?.attributes["src"];

      if (masterUrl == null) return videoList;

      final masterHeaders = Map<String, String>.from(headers)..addAll({
        "Accept": "*/*",
        "Host": Uri.parse(masterUrl).host,
        "Origin": "https://${Uri.parse(url).host}",
        "Referer": "https://${Uri.parse(url).host}/",
      });

      final masterPlaylistResponse = await client.get(
        Uri.parse(masterUrl),
        headers: masterHeaders,
      );
      final masterPlaylist = masterPlaylistResponse.body;

      final masterBase =
          "${"https://${Uri.parse(masterUrl).host}${Uri.parse(masterUrl).path}".substringBeforeLast("/")}/";

      masterPlaylist
          .substringAfter("#EXT-X-STREAM-INF:")
          .split("#EXT-X-STREAM-INF:")
          .forEach((it) {
        final quality =
            "Sendvid:${it.substringAfter("RESOLUTION=").substringAfter("x").substringBefore(",")}p ";
        final videoUrl =
            masterBase + it.substringAfter("\n").substringBefore("\n");

        final videoHeaders = Map<String, String>.from(headers)..addAll({
          "Accept": "*/*",
          "Host": Uri.parse(videoUrl).host,
          "Origin": "https://${Uri.parse(url).host}",
          "Referer": "https://${Uri.parse(url).host}/",
        });
        videoList.add(
          Video(
            videoUrl,
            "$prefix - $quality",
            videoUrl,
            headers: videoHeaders,
          ),
        );
      });

      return videoList;
    } catch (_) {
      return [];
    }
  }
}