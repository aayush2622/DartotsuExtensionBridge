import 'dart:collection';

import 'package:d4rt/d4rt.dart';

import '../../Models/Source.dart';
import '../../Util/interface.dart';
import '../javascript/http.dart';
import 'bridge/registrer.dart';
import 'model/filter.dart';
import 'model/m_manga.dart';
import 'model/m_pages.dart';
import 'model/page.dart';
import 'model/source_preference.dart';
import 'model/video.dart';

class DartExtensionService implements ExtensionService {
  @override
  late MSource source;

  DartExtensionService(this.source);

  D4rt? _interpreter;

  D4rt _executeLib() {
    final existing = _interpreter;
    if (existing != null) return existing;

    final interpreter = D4rt();
    RegistrerBridge.registerBridge(interpreter);

    interpreter.execute(
      source: source.sourceCode!.replaceAll('Client(source)', 'Client()'),
      args: source.toMSource(),
    );
    _interpreter = interpreter;
    return interpreter;
  }

  @override
  Map<String, String> getHeaders() {
    Map<String, String> headers = {};
    try {
      headers = _executeLib().invoke('headers', []) as Map<String, String>;
    } catch (_) {
      try {
        headers =
            _executeLib().invoke('getHeader', [source.baseUrl!])
                as Map<String, String>;
      } catch (_) {}
    }
    return headers;
  }

  @override
  String get sourceBaseUrl {
    String? baseUrl;
    try {
      final interpreter = _executeLib();
      baseUrl = interpreter.invoke('baseUrl', []) as String?;
    } catch (_) {}

    return baseUrl == null || baseUrl.isEmpty ? source.baseUrl! : baseUrl;
  }

  @override
  bool get supportsLatest {
    bool? supportsLatest;
    try {
      final interpreter = _executeLib();
      supportsLatest = interpreter.invoke('supportsLatest', []) as bool?;
    } catch (e) {
      supportsLatest = true;
    }
    return supportsLatest ?? true;
  }

  @override
  Future<MPages> getPopular(int page) async {
    final interpreter = _executeLib();
    final result = await interpreter.invoke('getPopular', [page]);
    return result as MPages;
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final interpreter = _executeLib();
    final result = await interpreter.invoke('getLatestUpdates', [page]);
    return result as MPages;
  }

  @override
  Future<MPages> search(String query, int page, List<dynamic> filters) async {
    final interpreter = _executeLib();
    final result = await interpreter.invoke('search', [
      query,
      page,
      FilterList(filters),
    ]);
    return result as MPages;
  }

  @override
  Future<MManga> getDetail(String url) async {
    final interpreter = _executeLib();
    final result = await interpreter.invoke('getDetail', [url]);
    return result as MManga;
  }

  @override
  Future<List<PageUrl>> getPageList(String url) async {
    final interpreter = _executeLib();
    final result = await interpreter.invoke('getPageList', [url]);

    // Matches the JS eval path (Eval/javascript/service.dart) - a null
    // entry here used to hit `e as Map` and throw TypeError, taking the
    // whole page list down; dedup by url the same way too.
    final pages = LinkedHashSet<PageUrl>(
      equals: (a, b) => a.url == b.url,
      hashCode: (p) => p.url.hashCode,
    );

    for (final e in result as List) {
      if (e == null) continue;
      final page = e is String
          ? PageUrl(e.toString().trim())
          : PageUrl.fromJson((e as Map).toMapStringDynamic!);
      pages.add(page);
    }

    return pages.toList();
  }

  @override
  Future<List<Video>> getVideoList(String url) async {
    final interpreter = _executeLib();
    final result = await interpreter.invoke('getVideoList', [url]);

    // Matches the JS eval path - a null entry used to hit .cast<Video>()
    // and throw, taking the whole video list down; dedup by
    // url+originalUrl the same way too.
    final videos = LinkedHashSet<Video>(
      equals: (a, b) => a.url == b.url && a.originalUrl == b.originalUrl,
      hashCode: (v) => Object.hash(v.url, v.originalUrl),
    );

    for (final e in result as List) {
      if (e is Video) videos.add(e);
    }

    return videos.toList();
  }

  @override
  Future<String> getHtmlContent(String url, String? referer) async {
    final interpreter = _executeLib();
    final result = await interpreter.invoke('getHtmlContent', [url, referer]);
    return result as String;
  }

  @override
  Future<String> cleanHtmlContent(String html) async {
    final interpreter = _executeLib();
    final result = await interpreter.invoke('cleanHtmlContent', [html]);
    return result as String;
  }

  @override
  FilterList getFilterList() {
    List<dynamic> list;
    try {
      final interpreter = _executeLib();
      list = interpreter.invoke('getFilterList', []) as List;
    } catch (_) {
      list = [];
    }

    return FilterList(_toValueList(list));
  }

  List _toValueList(List filters) {
    return (filters).map((e) {
      if (e is BridgedInstance) {
        e = e.nativeObject;
      }
      if (e is SelectFilter) {
        return SelectFilter(
          e.type,
          e.name,
          e.state,
          _toValueList(e.values),
          e.typeName,
        );
      } else if (e is SortFilter) {
        return SortFilter(
          e.type,
          e.name,
          e.state,
          _toValueList(e.values),
          e.typeName,
        );
      } else if (e is GroupFilter) {
        return GroupFilter(e.type, e.name, _toValueList(e.state), e.typeName);
      }
      return e;
    }).toList();
  }

  @override
  List<SourcePreference> getSourcePreferences() {
    try {
      final interpreter = _executeLib();
      final result = interpreter.invoke('getSourcePreferences', []);
      return (result as List).cast();
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    _interpreter = null;
  }
}
