import 'dart:async';

import 'package:jni/jni.dart';

import 'Generated/com/aayush262/dartotsu_extension_bridge/AniyomiExtensionApi.dart';

class AniyomiService {
  static final _api = AniyomiExtensionApi();

  static Future<dynamic> handle(
    String method,
    Map<String, dynamic> args,
  ) async {
    switch (method) {
      case "initialize":
        _api.initializeDesktop((args["path"] as String).toJString());
        return null;

      case "getInstalledAnimeExtensions":
        return await _api.getInstalledAnimeExtensions(
          (args["path"] as String?)?.toJString(),
        );

      case "getInstalledMangaExtensions":
        return await _api.getInstalledMangaExtensions(
          (args["path"] as String?)?.toJString(),
        );

      case "getPopular":
        return await _api.getPopular(
          (args["sourceId"] as String).toJString(),
          args["isAnime"],
          args["page"],
        );

      case "search":
        return await _api.search(
          (args["sourceId"] as String).toJString(),
          args["isAnime"],
          (args["query"] as String).toJString(),
          args["page"],
        );

      case "getDetail":
        return await _api.getDetail(
          (args["sourceId"] as String).toJString(),
          args["isAnime"],
          (args["media"] as String).toJString(),
        );

      case "getVideoList":
        return await _api.getVideoList(
          (args["sourceId"] as String).toJString(),
          args["isAnime"],
          (args["episode"] as String).toJString(),
        );

      case "getPageList":
        return await _api.getPageList(
          (args["sourceId"] as String).toJString(),
          args["isAnime"],
          (args["episode"] as String).toJString(),
        );

      case "getPreference":
        return await _api.getPreference(
          (args["sourceId"] as String).toJString(),
          args["isAnime"],
        );

      case "saveSourcePreference":
        return await _api.saveSourcePreference(
          (args["sourceId"] as String).toJString(),
          (args["key"] as String).toJString(),
          (args["value"] as String?)?.toJString(),
        );

      default:
        throw Exception("Unknown method: $method");
    }
  }
}
