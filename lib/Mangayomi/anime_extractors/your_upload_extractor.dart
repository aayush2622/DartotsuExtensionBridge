import '../string_extensions.dart';
import 'package:http_interceptor/http_interceptor.dart';

import '../Eval/dart/model/video.dart';
import '../http/m_client.dart';

class YourUploadExtractor {
  final InterceptedClient client = MClient.init(
    reqcopyWith: {'useDartHttpClient': true},
  );

  Future<List<Video>> videosFromUrl(
    String url,
    Map<String, String> headers, {
    String name = "YourUpload",
    String prefix = "",
  }) async {
    final newHeaders = Map<String, String>.from(headers);
    newHeaders["referer"] = "https://www.yourupload.com/";

    try {
      final response = await client.get(Uri.parse(url), headers: newHeaders);

      final body = response.body;
      final RegExp scriptRe = RegExp(
        r'<script[^>]*>([\s\S]*?)</script>',
        multiLine: true,
      );
      String? scriptContent;
      for (final m in scriptRe.allMatches(body)) {
        final inner = m.group(1);
        if (inner != null && inner.contains("jwplayerOptions")) {
          scriptContent = inner;
          break;
        }
      }

      if (scriptContent != null) {
        final basicUrl = scriptContent
            .substringAfter("file: '")
            .substringBefore("',");
        final quality = '$prefix$name';
        return [Video(basicUrl, quality, basicUrl, headers: newHeaders)];
      }

      // Fallback: no usable data
      return [];
    } catch (_) {
      return [];
    }
  }
}
