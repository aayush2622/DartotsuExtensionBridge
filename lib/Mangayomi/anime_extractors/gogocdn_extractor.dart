import 'dart:convert';
import 'dart:developer';

import 'package:dartotsu_extension_bridge/Mangayomi/cryptoaes/crypto_aes.dart';

import '../string_extensions.dart';
import 'package:html/parser.dart' as parser;
import 'package:http_interceptor/http_interceptor.dart';
import '../Eval/dart/model/video.dart';
import '../http/m_client.dart';

class GogoCdnExtractor {
  final InterceptedClient client = MClient.init(
    reqcopyWith: {'useDartHttpClient': true},
  );
  final JsonCodec json = const JsonCodec();

  Future<List<Video>> videosFromUrl(String serverUrl) async {
    try {
      final response = await client.get(Uri.parse(serverUrl));
      final document = response.body;
      final parsedResponse = parser.parse(response.body);

      final secretKey = parsedResponse
          .querySelector('body[class]')!
          .attributes["class"]!
          .split('container-')
          .last;

      final decryptionKey = RegExp(
        r'videocontent-(\d+)',
      ).firstMatch(document)?.group(1);

      final dataValue =
          RegExp(r'data-value="([^"]+)').firstMatch(document)?.group(1) ?? "";

      final encryptAjaxParams = CryptoAES.encryptAESCryptoJS(
        dataValue,
        secretKey,
      ).substringAfter("&");

      final httpUrl = Uri.parse(serverUrl);
      final id = httpUrl.queryParameters['id'];

      final encryptedId = CryptoAES.encryptAESCryptoJS(id ?? "", secretKey);

      final token = httpUrl.queryParameters['token'];
      final qualityPrefix = token != null ? "Gogostream - " : "Vidstreaming - ";

      final encryptAjaxUrl =
          "${httpUrl.scheme}://${httpUrl.host}/encrypt-ajax.php?id=$encryptedId&$encryptAjaxParams&alias=$id";

      final encryptAjaxResponse = await client.get(
        Uri.parse(encryptAjaxUrl),
        headers: {"X-Requested-With": "XMLHttpRequest"},
      );

      final jsonResponse = encryptAjaxResponse.body;
      final data = json.decode(jsonResponse)["data"];

      if (decryptionKey == null) return [];

      final decryptedData = CryptoAES.decryptAESCryptoJS(
        data ?? "",
        decryptionKey,
      );

      final videoList = <Video>[];
      final autoList = <Video>[];

      final array = json.decode(decryptedData)["source"];
      if (array != null &&
          array is List &&
          array.length == 1 &&
          array[0]["type"] == "hls") {
        final fileURL = array[0]["file"].toString().trim();
        const separator = "#EXT-X-STREAM-INF:";

        final masterPlaylistResponse = await client.get(Uri.parse(fileURL));
        final masterPlaylist = masterPlaylistResponse.body;

        if (masterPlaylist.contains(separator)) {
          for (var it
              in masterPlaylist.substringAfter(separator).split(separator)) {
            final quality =
                "${it.substringAfter("RESOLUTION=").substringAfter("x").substringBefore(",").substringBefore("\n")}p";

            var videoUrl = it.substringAfter("\n").substringBefore("\n");

            if (!videoUrl.startsWith("http")) {
              videoUrl =
                  "${fileURL.split("/").sublist(0, fileURL.split("/").length - 1).join("/")}/$videoUrl";
            }
            videoList.add(Video(videoUrl, "$qualityPrefix$quality", videoUrl));
          }
        } else {
          videoList.add(Video(fileURL, "${qualityPrefix}Original", fileURL));
        }
      } else if (array != null && array is List) {
        for (var it in array) {
          final label = it["label"].toString().toLowerCase().trim().replaceAll(
            " ",
            "",
          );
          final fileURL = it["file"].toString().trim();
          final videoHeaders = {"Referer": serverUrl};
          if (label == "auto") {
            autoList.add(
              Video(
                fileURL,
                "$qualityPrefix$label",
                fileURL,
                headers: videoHeaders,
              ),
            );
          } else {
            videoList.add(
              Video(
                fileURL,
                "$qualityPrefix$label",
                fileURL,
                headers: videoHeaders,
              ),
            );
          }
        }
      }

      return videoList + autoList;
    } catch (e) {
      log("Error in videosFromUrl: $e");
      return [];
    }
  }
}
