import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/Source.dart';
import '../../Models/SourcePreference.dart';
import '../../Models/Video.dart';
import '../../NetworkClient.dart';
import 'Models/LegadoSource.dart';
import 'RuleEngine/LegadoRuleEngine.dart';

/// Drives one [LegadoSource] entirely in Dart: fetch HTML with `MClient`,
/// pull fields out with [LegadoRuleEngine]. No JS runtime, no plugin binary.
class LegadoSourceMethods extends SourceMethods {
  @override
  final LegadoSource source;

  LegadoSourceMethods(Source source) : source = source as LegadoSource;

  static final http.Client _client = MClient.init();

  Map<String, String> _headers([Map<String, String>? extra]) {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,'
          'image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    };
    final raw = source.header?.trim();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) => headers[k.toString()] = v.toString());
        }
      } catch (_) {}
    }
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  /// Legado urls can be `url,{"method":"POST","body":"…","headers":{…}}`.
  Future<String> _fetch(String url) async {
    var actualUrl = url;
    var method = 'GET';
    String? body;
    final reqHeaders = _headers();

    final optionsIndex = url.indexOf(',{');
    if (optionsIndex != -1) {
      actualUrl = url.substring(0, optionsIndex);
      try {
        final opts = jsonDecode(url.substring(optionsIndex + 1));
        if (opts is Map) {
          if (opts['method'] != null) {
            method = opts['method'].toString().toUpperCase();
          }
          if (opts['body'] != null) body = opts['body'].toString();
          if (opts['headers'] is Map) {
            (opts['headers'] as Map).forEach(
              (k, v) => reqHeaders[k.toString()] = v.toString(),
            );
          }
        }
      } catch (_) {}
    }

    final uri = Uri.parse(actualUrl);
    final res = method == 'POST'
        ? await _client.post(uri, headers: reqHeaders, body: body)
        : await _client.get(uri, headers: reqHeaders);

    if (res.statusCode >= 200 && res.statusCode < 400) {
      return utf8.decode(res.bodyBytes, allowMalformed: true);
    }
    throw Exception('HTTP ${res.statusCode} for $actualUrl');
  }

  DMedia? _mediaFrom(dynamic el, Map<String, dynamic> rule) {
    final base = source.baseUrl ?? '';
    final title = LegadoRuleEngine.extractString(el, rule['name']?.toString());
    final bookUrl = LegadoRuleEngine.extractString(
      el,
      rule['bookUrl']?.toString(),
      baseUrl: base,
    );
    if (title.isEmpty || bookUrl.isEmpty) return null;

    final cover = LegadoRuleEngine.extractString(
      el,
      rule['coverUrl']?.toString(),
      baseUrl: base,
    );
    final author = LegadoRuleEngine.extractString(
      el,
      rule['author']?.toString(),
    );
    final intro = LegadoRuleEngine.extractString(el, rule['intro']?.toString());

    return DMedia(
      title: title,
      url: bookUrl,
      cover: cover.isNotEmpty ? cover : null,
      author: author.isNotEmpty ? author : null,
      description: intro.isNotEmpty ? intro : null,
    );
  }

  Future<Pages> _list(
    String urlTemplate,
    Map<String, dynamic>? rule,
    int page, {
    String query = '',
  }) async {
    if (urlTemplate.trim().isEmpty || rule == null) {
      return Pages(list: [], hasNextPage: false);
    }
    final url = LegadoRuleEngine.buildUrl(
      urlTemplate: urlTemplate,
      baseUrl: source.baseUrl ?? '',
      query: query,
      page: page,
    );
    final doc = LegadoRuleEngine.parseHtml(await _fetch(url));
    final elements = LegadoRuleEngine.selectElements(
      doc,
      rule['bookList']?.toString(),
    );

    final results = <DMedia>[];
    for (final el in elements) {
      final m = _mediaFrom(el, rule);
      if (m != null) results.add(m);
    }
    return Pages(list: results, hasNextPage: results.isNotEmpty);
  }

  @override
  Future<Pages> search(String query, int page, List<dynamic> filters) async {
    try {
      return await _list(
        source.searchUrl ?? '',
        source.ruleSearch ?? source.ruleExplore,
        page,
        query: query,
      );
    } catch (e, st) {
      Logger.log('[Legado] search error: $e\n$st');
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<Pages> getPopular(int page) => _explore(page, preferHot: true);

  @override
  Future<Pages> getLatestUpdates(int page) => _explore(page, preferHot: false);

  /// `exploreUrl` can be `Latest::url1\nHot::url2` — pick the section that
  /// matches, strip the `title::` prefix, then list it with `ruleExplore`.
  Future<Pages> _explore(int page, {required bool preferHot}) async {
    try {
      final template = source.exploreUrl;
      if (template == null || template.trim().isEmpty) {
        return Pages(list: [], hasNextPage: false);
      }
      final lines = template
          .split(RegExp(r'[\r\n]+'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isEmpty) return Pages(list: [], hasNextPage: false);

      String target;
      if (preferHot) {
        target = lines.firstWhere(
          (l) =>
              l.toLowerCase().contains('hot') ||
              l.toLowerCase().contains('popular') ||
              l.contains('热'),
          orElse: () => lines.length > 1 ? lines[1] : lines.first,
        );
      } else {
        target = lines.firstWhere(
          (l) =>
              l.toLowerCase().contains('latest') ||
              l.toLowerCase().contains('update') ||
              l.contains('新') ||
              l.contains('更'),
          orElse: () => lines.first,
        );
      }
      if (target.contains('::')) {
        target = target.substring(target.indexOf('::') + 2).trim();
      }

      return await _list(target, source.ruleExplore ?? source.ruleSearch, page);
    } catch (e, st) {
      Logger.log('[Legado] explore error: $e\n$st');
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<DMedia> getDetail(DMedia media) async {
    try {
      final bookUrl = media.url;
      if (bookUrl == null || bookUrl.isEmpty) return media;

      final base = source.baseUrl ?? '';
      final fullBookUrl = LegadoRuleEngine.resolveUrl(base, bookUrl);
      final doc = LegadoRuleEngine.parseHtml(await _fetch(fullBookUrl));

      final ruleBook = source.ruleBookInfo ?? const {};
      final title = LegadoRuleEngine.extractString(
        doc,
        ruleBook['name']?.toString(),
      );
      final cover = LegadoRuleEngine.extractString(
        doc,
        ruleBook['coverUrl']?.toString(),
        baseUrl: base,
      );
      final author = LegadoRuleEngine.extractString(
        doc,
        ruleBook['author']?.toString(),
      );
      final intro = LegadoRuleEngine.extractString(
        doc,
        ruleBook['intro']?.toString(),
      );
      final kind = LegadoRuleEngine.extractString(
        doc,
        ruleBook['kind']?.toString(),
      );

      final genres = kind.isEmpty
          ? null
          : kind
                .split(RegExp(r'[,/;\n\s]+'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();

      // The chapter list may live on a separate tocUrl page; that url can
      // itself be a `{{@@selector}}` template resolved against the book doc.
      dynamic tocDoc = doc;
      final rawTocUrl = ruleBook['tocUrl']?.toString();
      if (rawTocUrl != null && rawTocUrl.isNotEmpty) {
        var resolved = rawTocUrl;
        for (final m in RegExp(r'\{\{@@([^}]+)\}\}').allMatches(rawTocUrl)) {
          resolved = resolved.replaceFirst(
            m.group(0)!,
            LegadoRuleEngine.extractString(doc, m.group(1)),
          );
        }
        resolved = LegadoRuleEngine.resolveUrl(base, resolved);
        try {
          tocDoc = LegadoRuleEngine.parseHtml(await _fetch(resolved));
        } catch (e) {
          Logger.log('[Legado] toc fetch failed: $e — using book doc');
        }
      }

      final ruleToc = source.ruleToc ?? const {};
      final chapterElements = LegadoRuleEngine.selectElements(
        tocDoc,
        ruleToc['chapterList']?.toString(),
      );

      final chapters = <DEpisode>[];
      var epNum = 1;
      for (final el in chapterElements) {
        final name = LegadoRuleEngine.extractString(
          el,
          ruleToc['chapterName']?.toString() ?? 'text',
        );
        final url = LegadoRuleEngine.extractString(
          el,
          ruleToc['chapterUrl']?.toString() ?? 'href',
          baseUrl: base,
        );
        if (url.isEmpty) continue;
        chapters.add(
          DEpisode(
            name: name.isNotEmpty ? name : 'Chapter $epNum',
            url: url,
            episodeNumber: epNum.toString(),
          ),
        );
        epNum++;
      }

      return DMedia(
        title: title.isNotEmpty ? title : media.title,
        url: fullBookUrl,
        cover: cover.isNotEmpty ? cover : media.cover,
        author: author.isNotEmpty ? author : media.author,
        description: intro.isNotEmpty ? intro : media.description,
        genre: genres ?? media.genre,
        episodes: chapters.isNotEmpty ? chapters : media.episodes,
      );
    } catch (e, st) {
      Logger.log('[Legado] getDetail error: $e\n$st');
      return media;
    }
  }

  @override
  Future<String?> getNovelContent(DEpisode episode) async {
    try {
      var chapterUrl = episode.url ?? '';
      if (chapterUrl.isEmpty) return null;
      if (!chapterUrl.startsWith('http://') &&
          !chapterUrl.startsWith('https://')) {
        chapterUrl = LegadoRuleEngine.resolveUrl(
          source.baseUrl ?? '',
          chapterUrl,
        );
      }

      final ruleContent = source.ruleContent ?? const {};
      final selector = ruleContent['content']?.toString() ?? 'p@text';

      final buffer = StringBuffer();
      var url = chapterUrl;
      var guard = 0;
      final seen = <String>{};
      while (url.isNotEmpty && seen.add(url) && guard++ < 30) {
        final doc = LegadoRuleEngine.parseHtml(await _fetch(url));
        buffer.writeln(LegadoRuleEngine.extractString(doc, selector));

        final next = LegadoRuleEngine.extractString(
          doc,
          ruleContent['nextContentUrl']?.toString(),
          baseUrl: source.baseUrl ?? '',
        );
        url = next.isEmpty ? '' : next;
      }

      var content = buffer.toString();
      final replaceRegex = ruleContent['replaceRegex']?.toString();
      if (replaceRegex != null && replaceRegex.isNotEmpty) {
        for (final rep in LegadoRuleEngine.parseReplacements(
          replaceRegex.replaceFirst(RegExp(r'^##'), ''),
        )) {
          if (rep.isEmpty) continue;
          try {
            content = content.replaceAll(
              LegadoRuleEngine.cachedRegex(rep[0]),
              rep.length > 1 ? rep[1] : '',
            );
          } catch (_) {}
        }
      }
      return content.trim();
    } catch (e, st) {
      Logger.log('[Legado] getNovelContent error: $e\n$st');
      return null;
    }
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) async {
    final url = episode.url;
    return (url != null && url.isNotEmpty) ? [PageUrl(url)] : const [];
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async => const [];

  @override
  Future<List<SourcePreference>> getPreference() async => const [];

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async =>
      true;
}
