import 'dart:convert';
import 'dart:typed_data';

import '../../Engines/WasmEngine/WasmEngine.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import 'AidokuDefaults.dart';
import 'AidokuHome.dart';
import 'AidokuHost.dart';
import 'AidokuIo.dart';
import 'AidokuModels.dart';
import 'Postcard.dart';

class AidokuRuntime {
  AidokuRuntime._(this.engine, this.host, this._log);

  final void Function(String message) _log;

  final WasmEngine engine;
  final AidokuHost host;
  final Map<String, AManga> mangaCache = {};

  Future<void> _tail = Future.value();

  static Future<AidokuRuntime> load(
    String sourceId,
    String wasmBase64,
    Map<String, String>? defaults,
    AidokuIo io,
  ) async {
    final host = AidokuHost(
      sourceId,
      io: io,
      defaultValues: defaults ?? const {},
    );
    final engine = await WasmEngine.instantiate(
      base64Decode(wasmBase64),
      host.build(),
    );
    host.engine = engine;
    await engine.call('start', const []);
    return AidokuRuntime._(engine, host, io.log);
  }

  String _describeFailure(String export, int code) {
    final reason = switch (code) {
      -2 => 'not implemented by this source',
      -3 => 'a network request failed${_netDetail()}',
      -4 => 'the page could not be parsed (HTML)',
      -5 => 'a JavaScript call failed',
      -6 => 'an image operation failed',
      -7 => 'invalid text encoding',
      -8 => 'invalid JSON',
      -9 => 'unexpected data',
      _ => 'code $code',
    };
    return 'Aidoku source "$export" failed: $reason';
  }

  String _netDetail() {
    final error = host.lastNetError;
    if (error == null) return '';
    final text = error.length > 200 ? '${error.substring(0, 200)}...' : error;
    return ' ($text)';
  }

  Future<T> _serial<T>(Future<T> Function() run) {
    final next = _tail.then((_) {
      host.lastNetError = null;
      return run();
    });
    _tail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<Pages> getPopular(int page) =>
      _serial(() => _listed(_popularPattern, page));

  Future<Pages> getLatestUpdates(int page) =>
      _serial(() => _listed(_latestPattern, page));

  Future<Pages> search(String query, int page) =>
      _serial(() => _search(query, page));

  Future<void> notify(String name) => _serial(() async {
    if (!engine.hasExport('handle_notification')) return;
    final w = PostcardWriter()..writeString(name);
    final rid = host.bufferResource(w.takeBytes());
    final code = (await engine.call('handle_notification', [rid]) as num)
        .toInt();
    if (code < 0) _log('handle_notification $name returned $code');
  });

  Future<bool> basicLogin(String key, String user, String password) =>
      _serial(() async {
        if (!engine.hasExport('handle_basic_login')) return false;
        int rid(String v) =>
            host.bufferResource((PostcardWriter()..writeString(v)).takeBytes());
        return _callExport('handle_basic_login', [
          rid(key),
          rid(user),
          rid(password),
        ], (r) => r.readBool());
      });

  Future<DMedia> getDetail(DMedia media) => _serial(() => _getDetail(media));

  Future<List<PageUrl>> getPageList(DEpisode episode) =>
      _serial(() => _getPageList(episode));

  Future<T> _callExport<T>(
    String export,
    List<Object?> args,
    T Function(PostcardReader) decode,
  ) async {
    final raw = await engine.call(export, args);
    final ptr = (raw as num).toInt();
    if (ptr < 0) {
      throw Exception(_describeFailure(export, ptr));
    }

    try {
      final header = engine.readBytes(ptr, 8);
      final headerView = ByteData.sublistView(header);
      final totalLen = headerView.getInt32(0, Endian.little);

      if (totalLen == -1) {
        final totalBufLenBytes = engine.readBytes(ptr + 8, 4);
        final totalBufLen = ByteData.sublistView(
          totalBufLenBytes,
        ).getInt32(0, Endian.little);
        final messageLen = totalBufLen - 12;
        final message = messageLen <= 0
            ? ''
            : utf8.decode(engine.readBytes(ptr + 12, messageLen));
        throw Exception('Aidoku source "$export" error: $message');
      }

      final payload = engine.readBytes(ptr + 8, totalLen - 8);
      return decode(PostcardReader(payload));
    } finally {
      await engine.call('free_result', [ptr]);
    }
  }

  static final _popularPattern = RegExp(
    r'popular|trending|hot|top|view|rank|best|популяр|人気|最も|热门|熱門|인기',
    caseSensitive: false,
  );
  static final _latestPattern = RegExp(
    r'latest|update|recent|new|fresh|последн|обновл|最新|更新|新着|新作|최신',
    caseSensitive: false,
  );

  List<({String id, String name})>? _listings;

  Future<List<({String id, String name})>> _loadListings() async {
    final known = _listings;
    if (known != null) return known;
    final found = <({String id, String name})>[];
    final raw = host.defaultValues[aidokuListingsKey];
    if (raw != null) {
      for (final entry in jsonDecode(raw) as List) {
        final pair = (entry as List).cast<String>();
        found.add((id: pair[0], name: pair[1]));
      }
    }
    if (engine.hasExport('get_listings')) {
      try {
        final dynamic = await _callExport('get_listings', const [], (r) {
          return r.readVec(() {
            final id = r.readString();
            final name = r.readString();
            r.readVarU();
            return (id: id, name: name);
          });
        });
        for (final l in dynamic) {
          if (!found.any((f) => f.id == l.id)) found.add(l);
        }
      } catch (e) {
        _log('get_listings failed: $e');
      }
    }
    return _listings = found;
  }

  Future<Pages> _listed(RegExp pattern, int page) async {
    if (!engine.hasExport('get_manga_list')) {
      return _homeOrSearch(pattern, page);
    }
    final listings = await _loadListings();
    if (listings.isEmpty) return _homeOrSearch(pattern, page);
    final other = pattern == _popularPattern ? _latestPattern : _popularPattern;
    var pick = listings.where((l) => pattern.hasMatch(l.name)).firstOrNull;
    pick ??= listings.where((l) => !other.hasMatch(l.name)).firstOrNull;
    pick ??= listings.first;
    final writer = PostcardWriter()
      ..writeString(pick.id)
      ..writeString(pick.name)
      ..writeVarU(0);
    final listingRid = host.bufferResource(writer.takeBytes());
    try {
      final result = await _callExport('get_manga_list', [
        listingRid,
        page,
      ], AMangaPageResult.decode);
      for (final manga in result.entries) {
        mangaCache[manga.key] = manga;
      }
      return Pages(
        list: result.entries.map(_mangaToDMedia).toList(),
        hasNextPage: result.hasNextPage,
      );
    } catch (e) {
      _log('listing "${pick.name}" failed, using search: $e');
      return _search(null, page);
    }
  }

  Future<Pages> _homeOrSearch(RegExp pattern, int page) async {
    if (!engine.hasExport('get_home')) return _search(null, page);
    List<AHomeComponent> home;
    try {
      home = await _callExport('get_home', const [], decodeAidokuHome);
    } catch (e) {
      _log('get_home failed, using search: $e');
      return _search(null, page);
    }
    final withManga = home.where((c) => c.mangas.isNotEmpty).toList();
    if (withManga.isEmpty) return _search(null, page);
    final other = pattern == _popularPattern ? _latestPattern : _popularPattern;
    final pick =
        withManga.where((c) => pattern.hasMatch(c.title ?? '')).firstOrNull ??
        withManga.where((c) => !other.hasMatch(c.title ?? '')).firstOrNull ??
        withManga.first;
    if (page > 1) return Pages(list: const [], hasNextPage: false);
    for (final manga in pick.mangas) {
      mangaCache[manga.key] = manga;
    }
    return Pages(
      list: pick.mangas.map(_mangaToDMedia).toList(),
      hasNextPage: false,
    );
  }

  int _emptyFiltersRid() {
    final writer = PostcardWriter()..writeVarU(0);
    return host.bufferResource(writer.takeBytes());
  }

  Future<Pages> _search(String? query, int page) async {
    final queryRid = host.stringResource(query ?? '');
    final filtersRid = _emptyFiltersRid();

    final result = await _callExport('get_search_manga_list', [
      queryRid,
      page,
      filtersRid,
    ], AMangaPageResult.decode);

    for (final manga in result.entries) {
      mangaCache[manga.key] = manga;
    }

    return Pages(
      list: result.entries.map(_mangaToDMedia).toList(),
      hasNextPage: result.hasNextPage,
    );
  }

  DMedia _mangaToDMedia(AManga manga) => DMedia(
    title: manga.title,
    url: manga.key,
    cover: manga.cover,
    description: manga.description,
    author: manga.authors?.join(', '),
    artist: manga.artists?.join(', '),
    genre: manga.tags,
  );

  AManga _mangaFromMedia(DMedia media) {
    final key = media.url ?? media.title ?? '';
    return mangaCache[key] ??
        AManga(key: key, title: media.title ?? '', cover: media.cover);
  }

  Future<DMedia> _getDetail(DMedia media) async {
    final manga = _mangaFromMedia(media);

    final writer = PostcardWriter();
    manga.encode(writer);
    final mangaRid = host.bufferResource(writer.takeBytes());

    final updated = await _callExport('get_manga_update', [
      mangaRid,
      1,
      1,
    ], AManga.decode);
    mangaCache[updated.key] = updated;

    final chapters = updated.chapters ?? const <AChapter>[];
    _log(
      'getDetail chapters sample: '
      '${chapters.take(3).map((c) => '(key=${c.key}, title=${c.title}, num=${c.chapterNumber})').join(', ')}'
      '${chapters.length > 3 ? ' ... last=(key=${chapters.last.key}, title=${chapters.last.title}, num=${chapters.last.chapterNumber})' : ''}',
    );
    final episodes = chapters.map(_chapterToDEpisode).toList();

    return _mangaToDMedia(updated)..episodes = episodes;
  }

  String _floatNumber(double? value) {
    if (value == null || !value.isFinite) return '';
    if (value == value.roundToDouble()) return value.toInt().toString();
    final single = Float32List(1);
    for (var digits = 1; digits <= 9; digits++) {
      final text = value.toStringAsPrecision(digits);
      single[0] = double.parse(text);
      if (single[0] == value) {
        return text.contains('e') ? text : double.parse(text).toString();
      }
    }
    return value.toString();
  }

  DEpisode _chapterToDEpisode(AChapter chapter) {
    final numberStr = _floatNumber(chapter.chapterNumber);

    return DEpisode(
      url: chapter.key,
      name: chapter.title,
      dateUpload: chapter.dateUploaded?.toString(),
      scanlator: chapter.scanlators?.join(', '),
      thumbnail: chapter.thumbnail,
      episodeNumber: numberStr,
    );
  }

  AChapter _chapterFromEpisode(DEpisode episode) {
    return AChapter(
      key: episode.url ?? '',
      title: episode.name,
      chapterNumber: double.tryParse(episode.episodeNumber),
      url: episode.url,
      thumbnail: episode.thumbnail,
      scanlators: episode.scanlator == null ? null : [episode.scanlator!],
    );
  }

  Future<List<Map<String, Object?>>> getPageDescriptors(
    DEpisode episode,
  ) async {
    final pages = await getPageList(episode);
    final processes = engine.hasExport('process_page_image');
    return [
      for (final p in pages)
        {
          'url': p.url,
          'headers': p.headers,
          'context': _lastContexts[p.url],
          'process': processes,
        },
    ];
  }

  final Map<String, Map<String, String>?> _lastContexts = {};

  Future<List<PageUrl>> _getPageList(DEpisode episode) async {
    _lastContexts.clear();
    final manga = mangaCache[episode.url] ?? _lastManga();
    if (manga == null) {
      throw Exception('No manga context available for this chapter');
    }

    final mangaWriter = PostcardWriter();
    manga.encode(mangaWriter);
    final mangaRid = host.bufferResource(mangaWriter.takeBytes());

    final chapter = _chapterFromEpisode(episode);
    final chapterWriter = PostcardWriter();
    chapter.encode(chapterWriter);
    final chapterRid = host.bufferResource(chapterWriter.takeBytes());

    final pages = await _callExport('get_page_list', [
      mangaRid,
      chapterRid,
    ], (r) => r.readVec(() => APage.decode(r)));

    final processes = engine.hasExport('process_page_image');
    final requests = engine.hasExport('get_image_request');
    final out = <PageUrl>[];
    for (final p in pages) {
      if (p.contentKind != 0 || p.contentUrl == null) continue;
      var url = p.contentUrl!;
      var headers = <String, String>{};
      if (requests) {
        try {
          final request = await _imageRequest(url, p.context);
          url = request.url ?? url;
          headers = request.headers;
        } catch (_) {}
      }
      final context = p.context;
      final pageUrl = url;
      final pageHeaders = headers;
      _lastContexts[pageUrl] = context;
      out.add(
        PageUrl(
          pageUrl,
          headers: pageHeaders.isEmpty ? null : pageHeaders,
          process: processes
              ? (data) => processPageImage(
                  data,
                  url: pageUrl,
                  headers: pageHeaders,
                  context: context,
                )
              : null,
        ),
      );
    }
    return out;
  }

  Future<({String? url, Map<String, String> headers})> _imageRequest(
    String url,
    Map<String, String>? context,
  ) async {
    final urlWriter = PostcardWriter()..writeString(url);
    final urlRid = host.bufferResource(urlWriter.takeBytes());
    final contextRid = _contextRid(context);
    return _callExport('get_image_request', [urlRid, contextRid], (r) {
      final requestUrl = r.readOption(r.readString);
      return (url: requestUrl, headers: r.readStringMap());
    });
  }

  int _contextRid(Map<String, String>? context) {
    if (context == null) return -1;
    final writer = PostcardWriter()..writeVarU(context.length);
    for (final e in context.entries) {
      writer
        ..writeString(e.key)
        ..writeString(e.value);
    }
    return host.bufferResource(writer.takeBytes());
  }

  Future<Uint8List> processPageImage(
    Uint8List data, {
    required String url,
    Map<String, String> headers = const {},
    Map<String, String>? context,
  }) => _serial(() async {
    final imageRid = host.decodeImageResource(data);
    if (imageRid < 0) throw Exception('Could not decode the page image');
    final writer = PostcardWriter()
      ..writeVarU(200)
      ..writeVarU(0);
    writer.writeOption<String>(url, writer.writeString);
    writer.writeVarU(headers.length);
    for (final e in headers.entries) {
      writer
        ..writeString(e.key)
        ..writeString(e.value);
    }
    writer.writeVarI(imageRid);
    final responseRid = host.bufferResource(writer.takeBytes());
    final contextRid = _contextRid(context);
    var resultRid = -1;
    try {
      resultRid = await _callExport('process_page_image', [
        responseRid,
        contextRid,
      ], (r) => r.readVarI());
      final bytes = host.encodeImageResource(resultRid);
      if (bytes == null) throw Exception('The source returned no image');
      return bytes;
    } finally {
      for (final rid in [imageRid, responseRid, contextRid, resultRid]) {
        if (rid >= 0) host.release(rid);
      }
    }
  });

  AManga? _lastManga() =>
      mangaCache.values.isEmpty ? null : mangaCache.values.last;
}
