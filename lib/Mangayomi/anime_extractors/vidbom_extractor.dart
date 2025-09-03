import '../string_extensions.dart';
import 'package:http_interceptor/http_interceptor.dart';

import '../Eval/dart/model/video.dart';
import '../http/m_client.dart';

class VidBomExtractor {
  final InterceptedClient client = MClient.init(
    reqcopyWith: {'useDartHttpClient': true},
  );

  Future<List<Video>> videosFromUrl(String url) async {
    try {
      final response = await client.get(Uri.parse(url));

      final body = response.body;

      final RegExp scriptRe = RegExp(
        r'<script[^>]*>([\s\S]*?)</script>',
        multiLine: true,
      );
      String? scriptContent;
      for (final m in scriptRe.allMatches(body)) {
        final inner = m.group(1);
        if (inner != null && inner.contains('sources')) {
          scriptContent = inner;
          break;
        }
      }
      if (scriptContent == null) return [];

      final data = scriptContent.substringAfter('sources: [');

      final List<Video> results = [];
      if (data.isNotEmpty) {
        final files = data.split('file:"').skip(1);
        for (var src in files) {
          final fileUrl = src.substringBefore('"');
          final label = src.contains('label:"')
              ? src.substringAfter('label:"').substringBefore('"')
              : '';
          var quality = label.isNotEmpty ? label : 'Vidbom';
          results.add(Video(fileUrl, quality, fileUrl));
        }
      }

      return results;
    } catch (_) {
      return [];
    }
  }
}
