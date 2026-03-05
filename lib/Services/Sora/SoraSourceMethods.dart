import 'dart:async';
import 'dart:convert';

import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/Source.dart';
import '../../Models/SourcePreference.dart';
import '../../Models/Video.dart';
import '../Mangayomi/http/m_client.dart';
import 'JsEngine/JsEngine.dart';
import 'Models/Source.dart';

class SoraSourceMethods extends SourceMethods {
  @override
  final SSource source;

  late final String module = source.name ?? source.id ?? "";

  SoraSourceMethods(Source source) : source = source as SSource;

  Completer<void>? _initCompleter;

  Future<void> initialize() {
    if (_initCompleter?.isCompleted ?? false) {
      return _initCompleter!.future;
    }

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    _doInitialize();

    return _initCompleter!.future;
  }

  Future<void> _doInitialize() async {
    try {
      String code = source.sourceCode ?? "";

      if (code.isEmpty && source.sourceCodeUrl != null) {
        final client = MClient.init();
        final res = await client.get(Uri.parse(source.sourceCodeUrl!));
        code = res.body;
      }

      await JsExtensionEngine.instance.loadModule(
        moduleName: module,
        sourceCode: code,
      );

      _initCompleter?.complete();
    } catch (e, stack) {
      _initCompleter?.completeError(e, stack);
      _initCompleter = null;
    }
  }

  dynamic _parseJs(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return value;
      }
    }

    return value;
  }

  Future<dynamic> _call(String method, List params) async {
    try {
      final res = await JsExtensionEngine.instance.call(
        moduleName: module,
        method: method,
        params: params,
      );

      return _parseJs(res.value);
    } catch (e) {
      Logger.log("Error calling JS method '$method': $e");
      return null;
    }
  }

  void _collectEpisodes(dynamic data, List<DEpisode> episodes) {
    void add(Map e, {String? fallback}) {
      episodes.add(
        DEpisode(
          episodeNumber: e["number"]?.toString() ??
              e["chapter"]?.toString() ??
              fallback ??
              "",
          url: e["href"] ?? e["id"],
          name: e["title"],
          scanlator: e["scanlation_group"] ?? e["scanlator_group"],
        ),
      );
    }

    if (data is List) {
      for (final e in data) {
        if (e is Map) add(Map<String, dynamic>.from(e));
      }
    } else if (data is Map) {
      for (final group in data.values) {
        if (group is List) {
          for (final item in group) {
            if (item is List && item.length >= 2) {
              final number = item[0];
              final list = item[1];

              if (list is List) {
                for (final e in list) {
                  if (e is Map) {
                    add(
                      Map<String, dynamic>.from(e),
                      fallback: number?.toString(),
                    );
                  }
                }
              }
            } else if (item is Map) {
              add(Map<String, dynamic>.from(item));
            }
          }
        }
      }
    }
  }

  @override
  Future<DMedia> getDetail(DMedia media) async {
    await initialize();

    final details = await _call("extractDetails", [media.url]);

    final resultMedia = DMedia(
      title: details?["title"] ?? media.title,
      url: details?["url"] ?? media.url,
      cover: details?["cover"] ?? media.cover,
      description: details?["description"],
    );

    final method = source.itemType == ItemType.anime
        ? "extractEpisodes"
        : "extractChapters";

    final rawEpisodes = await _call(method, [media.url]);

    final episodes = <DEpisode>[];
    _collectEpisodes(rawEpisodes, episodes);

    resultMedia.episodes = episodes;

    return resultMedia;
  }

  @override
  Future<Pages> search(String query, int page, List<dynamic> filters) async {
    await initialize();

    final raw = await _call("searchResults", [query, page, filters]);

    if (raw == null || raw is! List) {
      return Pages(list: []);
    }

    if (raw.length == 1 && raw[0]['title'] == 'Error') {
      return Pages(list: []);
    }

    final list = raw.map<DMedia>((e) {
      final map = Map<String, dynamic>.from(e);

      return DMedia(
        title: map['title'],
        url: map['href'] ?? map['id'],
        cover: map['image'] ?? map['imageURL'],
      );
    }).toList();

    return Pages(list: list);
  }

  @override
  Future<Pages> getLatestUpdates(int page) => search("One Piece", page, []);

  @override
  Future<Pages> getPopular(int page) => search("One Piece", page, []);

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) async {
    await initialize();

    final data = await _call("extractImages", [episode.url]);

    final pages = <PageUrl>[];

    if (data is List) {
      for (final item in data) {
        if (item is String) {
          pages.add(PageUrl(item));
        }
      }
    }

    return pages;
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async {
    await initialize();

    final data = await _call("extractStreamUrl", [episode.url]);

    final videos = <Video>[];

    Map<String, String> defaultHeaders = {
      "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.131 Safari/537.36",
    };

    void addVideo(String title, String url,
        {Map<String, String>? headers, List<Track>? subtitles}) {
      videos.add(
        Video(
          title,
          url,
          "auto",
          headers: headers ?? defaultHeaders,
          subtitles: subtitles ?? [],
        ),
      );
    }

    if (data is String) {
      addVideo("Video", data);
      return videos;
    }

    if (data is Map && data.containsKey("stream")) {
      final subs = <Track>[];

      if (data["subtitles"] != null) {
        subs.add(Track(file: data["subtitles"], label: "Default"));
      }

      addVideo("Video", data["stream"], subtitles: subs);
      return videos;
    }

    if (data is Map && data["streams"] is Map) {
      (data["streams"] as Map).forEach((key, value) {
        if (value != null) {
          addVideo(key.toString(), value.toString());
        }
      });

      return videos;
    }

    if (data is Map && data["streams"] is List) {
      for (final stream in data["streams"]) {
        final url =
            stream["streamUrl"] ?? stream["url"] ?? stream["stream"] ?? "";

        if (url.isEmpty) continue;

        final title = stream["title"] ?? "Server";

        final headers = (stream["headers"] as Map?)?.cast<String, String>();

        List<Track> subs = [];

        if (stream["subtitles"] is List) {
          subs = (stream["subtitles"] as List)
              .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }

        videos.add(
          Video(
            title,
            url,
            "auto",
            headers: headers,
            subtitles: subs,
          ),
        );
      }
    }

    return videos;
  }

  @override
  Future<List<SourcePreference>> getPreference() => Future.value([]);

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId) {
    throw UnimplementedError();
  }

  @override
  Future<bool> setPreference(SourcePreference pref, value) {
    throw UnimplementedError();
  }
}
