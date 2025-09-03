import 'dart:math';

import 'package:http_interceptor/http_interceptor.dart';

import '../Eval/dart/model/video.dart';
import '../http/m_client.dart';

class DoodExtractor {
  Future<List<Video>> videosFromUrl(
    String url, {
    String? quality,
    bool redirect = true,
  }) async {
    final InterceptedClient client = MClient.init(
      reqcopyWith: {'useDartHttpClient': true},
    );

    final newQuality = (quality ?? "Doodstream${redirect ? ' mirror' : ''}");

    try {
      final response = await client.get(Uri.parse(url));

      final String effectiveUrl = redirect
          ? (response.request?.url.toString() ?? url)
          : url;

      final RegExp hostRegex = RegExp(r'https://(.*?)/');
      final String? doodHost = hostRegex.firstMatch(effectiveUrl)?.group(1);

      if (doodHost == null || doodHost.isEmpty) {
        return [];
      }

      final String content = response.body;

      const String passMd5Marker = "'/pass_md5/";
      if (!content.contains(passMd5Marker)) return [];

      final int passIndex = content.indexOf(passMd5Marker);
      if (passIndex == -1) return [];

      final String afterPassMd5 = content.substring(
        passIndex + passMd5Marker.length,
      );
      final int endQuote = afterPassMd5.indexOf("',");
      if (endQuote == -1) return [];

      final String md5 = afterPassMd5.substring(0, endQuote);
      if (md5.isEmpty) return [];
      final String token = md5.substring(md5.lastIndexOf('/') + 1);
      final String randomString = _getRandomString(length: 10);
      final int expiry = DateTime.now().millisecondsSinceEpoch;

      final videoUrlStart = await client.get(
        Uri.parse('https://$doodHost/pass_md5/$md5'),
        headers: {'referer': effectiveUrl},
      );

      final String videoUrlPart = videoUrlStart.body;
      if (videoUrlPart.isEmpty) return [];

      final String videoUrl =
          '$videoUrlPart$randomString?token=$token&expiry=$expiry';

      return [
        Video(
          effectiveUrl,
          newQuality,
          videoUrl,
          headers: {'User-Agent': 'Mangayomi', 'Referer': 'https://$doodHost/'},
        ),
      ];
    } catch (e) {
      return [];
    }
  }

  String _getRandomString({int length = 10}) {
    const allowedChars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final List<int> codes = List.generate(
      length,
      (_) => allowedChars.codeUnitAt(Random().nextInt(allowedChars.length)),
    );
    return String.fromCharCodes(codes);
  }
}
