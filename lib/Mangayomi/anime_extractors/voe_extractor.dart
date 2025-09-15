import 'dart:convert';

import '../string_extensions.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'package:http_interceptor/http_interceptor.dart';
import 'package:path/path.dart' as path;

import '../Eval/dart/model/video.dart';
import '../http/m_client.dart';

class VoeExtractor {
  final InterceptedClient client = MClient.init(
    reqcopyWith: {'useDartHttpClient': true},
  );
  final linkRegex = RegExp(
    r'(http|https)://([\w_-]+(?:\.[\w_-]+)+)([\w.,@?^=%&:/~+#-]*[\w@?^=%&/~+#-])',
  );

  final base64Regex = RegExp(r"'.*'");
  final RegExp scriptBase64Regex = RegExp(
    r"(let|var)\s+\w+\s*=\s*'(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)';",
  );

  Future<List<Video>> videosFromUrl(String url, String? prefix) async {
    try {
      final response = await client.get(Uri.parse(url));
      final document = parse(response.body);
      var scriptElement = document.querySelector("script");
      if (scriptElement?.text.contains(
            "if (typeof localStorage !== 'undefined')",
          ) ??
          false) {
        final originalUrl = scriptElement?.text
            .substringAfter("window.location.href = '")
            .substringBefore("';");
        if (originalUrl == null) return [];
        final r2 = await client.get(Uri.parse(originalUrl));
        final document2 = parse(r2.body);
        scriptElement = document2.querySelector("script");
      }

      Element? script = document.querySelector(
        "script:contains(const sources), script:contains(var sources), script:contains(wc0)",
      );
      script ??= document.querySelector("script");
      final scriptContent = script?.text ?? '';
      String playlistUrl = '';

      if (scriptContent.contains('sources')) {
        final link = scriptContent
            .substringAfter("hls': '")
            .substringBefore("'");
        playlistUrl = link;
      } else if (scriptContent.contains('wc0')) {
        // fallback parsing
        final base64Match = scriptContent.contains(scriptBase64Regex.pattern)
            ? scriptContent.substringAfter("'").substringBefore("'")
            : null;
        if (base64Match != null) {
          final decoded = base64.decode(base64Match);
          playlistUrl = String.fromCharCodes(decoded);
        }
      } else {
        return [];
      }

      final uri = Uri.parse(playlistUrl);
      final m3u8Host = "${uri.scheme}://${uri.host}${path.dirname(uri.path)}";
      final masterPlaylistResponse = await client.get(uri);
      final masterPlaylist = masterPlaylistResponse.body;

      const separator = "#EXT-X-STREAM-INF";
      return masterPlaylist.substringAfter(separator).split(separator).map((
        it,
      ) {
        final resolution =
            "${it.substringAfter("RESOLUTION=").substringBefore("\n").substringAfter("x").substringBefore(",")}p";
        final line = it.substringAfter("\n").substringBefore("\n");
        final videoUrl = line.startsWith("http")
            ? line
            : "$m3u8Host/${line.replaceAll(RegExp(r"^/"), '')}";
        return Video(videoUrl, '${prefix ?? ""}Voe: $resolution', videoUrl);
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
