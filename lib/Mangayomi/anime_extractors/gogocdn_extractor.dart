import 'dart:convert';
import 'dart:developer';

import '../string_extensions.dart';
import 'package:html/parser.dart' as parser;
import 'package:http_interceptor/http_interceptor.dart';

import '../Eval/dart/model/m_bridge.dart';
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

      final iv = parsedResponse
          .querySelector('div.wrapper')!
          .attributes["class"]!
          .split('container-')
          .last;

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

      // Await cryptoHandler if it's async
      final encryptAjaxParams = (await MBridge.cryptoHandler(
        dataValue,
        iv,
        secretKey,
        false,
      )).substringAfter("&"); // now valid, because it's a String

      final httpUrl = Uri.parse(serverUrl);
      final host = "https://${httpUrl.host}/";
      final id = httpUrl.queryParameters['id'];
      final encryptedId = await MBridge.cryptoHandler(
        id ?? "",
        iv,
        secretKey,
        true,
      );

      final token = httpUrl.queryParameters['token'];
      final qualityPrefix = token != null ? "Gogostream - " : "Vidstreaming - ";

      final encryptAjaxUrl =
          "${host}encrypt-ajax.php?id=$encryptedId&$encryptAjaxParams&alias=$id";

      final encryptAjaxResponse = await client.get(
        Uri.parse(encryptAjaxUrl),
        headers: {"X-Requested-With": "XMLHttpRequest"},
      );

      final jsonResponse = encryptAjaxResponse.body;
      final data = json.decode(jsonResponse)["data"];

      if (decryptionKey == null) return [];

      final decryptedData = await MBridge.cryptoHandler(
        data ?? "",
        iv,
        decryptionKey,
        false,
      ); // awaited here

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
