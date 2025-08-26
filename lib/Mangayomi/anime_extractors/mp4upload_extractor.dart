import 'dart:convert';
import 'package:http_interceptor/http_interceptor.dart';

import '../Eval/dart/model/video.dart';
import '../http/m_client.dart';
import '../string_extensions.dart';

class Mp4uploadExtractor {
  static final RegExp qualityRegex = RegExp(r'HEIGHT=(\d+)');
  static const String referer = "https://mp4upload.com/";
  final InterceptedClient client = MClient.init(
    reqcopyWith: {'useDartHttpClient': true},
  );

  Future<List<Video>> videosFromUrl(
    String url,
    Map<String, String> headers, {
    String prefix = '',
    String suffix = '',
  }) async {
    final newHeaders = Map<String, String>.from(headers)
      ..addAll({'referer': referer});
    try {
      final response = await client.get(Uri.parse(url), headers: newHeaders);
      final String body = response.body;

      final RegExp scriptTagRe = RegExp(
        r'<script[^>]*>([\s\S]*?)<\/script>',
        multiLine: true,
      );
      String? scriptContent;

      for (final m in scriptTagRe.allMatches(body)) {
        final inner = m.group(1);
        if (inner != null &&
            (inner.contains('eval') || inner.contains('player.src'))) {
          scriptContent = inner;
          break;
        }
      }

      if (scriptContent == null) return [];

      final String scriptUnpacked = scriptContent;

      String videoUrl = _extractVideoUrlFromScript(scriptUnpacked);

      final Match? resMatch = qualityRegex.firstMatch(scriptUnpacked);
      final String resolution = resMatch?.group(1) != null
          ? '${resMatch!.group(1)}'
          : 'Unknown';
      final String quality = '$prefix Mp4Upload - ${resolution}p $suffix';

      if (videoUrl.isEmpty) return [];

      return [Video(videoUrl, quality, videoUrl, headers: newHeaders)];
    } catch (_) {
      return [];
    }
  }

  String _extractVideoUrlFromScript(String script) {
    final RegExp r1 = RegExp(
      r'''src\s*[:=]\s*(['"])([^'"\\]+(?:\\.[^'"\\]*)*)\1''',
      caseSensitive: false,
    );
    final m1 = r1.firstMatch(script);
    if (m1 != null && m1.group(1) != null && m1.group(1)!.isNotEmpty) {
      return m1.group(1)!;
    }

    final RegExp r2 = RegExp(
      r'''\.src\s*\(\s*(['"])([^'"\\]+(?:\\.[^'"\\]*)*)\1\s*\)''',
      caseSensitive: false,
    );
    final m2 = r2.firstMatch(script);
    if (m2 != null && m2.group(1) != null && m2.group(1)!.isNotEmpty) {
      return m2.group(1)!;
    }

    final RegExp r3 = RegExp(
      r'''(['"])(https?:\/\/[^'"\\]*?\.mp4(?:[^'"\\]*?)?)\1''',
      caseSensitive: false,
    );
    final m3 = r3.firstMatch(script);
    if (m3 != null && m3.group(1) != null && m3.group(1)!.isNotEmpty) {
      return m3.group(1)!;
    }

    return '';
  }
}
