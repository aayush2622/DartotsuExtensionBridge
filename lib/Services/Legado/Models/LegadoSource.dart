import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../Models/Source.dart';

/// A Legado (阅读) book source — a JSON "书源" carrying its own HTML parse
/// rules. Unlike the other novel backends there is no plugin binary: the
/// [ruleSearch] / [ruleExplore] / [ruleBookInfo] / [ruleToc] / [ruleContent]
/// maps are the whole extension, evaluated by `LegadoRuleEngine`.
class LegadoSource extends Source {
  String? bookSourceName;
  String? bookSourceUrl;
  String? bookSourceGroup;
  int? bookSourceType;
  String? bookSourceComment;
  String? searchUrl;
  String? exploreUrl;
  String? header;
  Map<String, dynamic>? ruleSearch;
  Map<String, dynamic>? ruleExplore;
  Map<String, dynamic>? ruleBookInfo;
  Map<String, dynamic>? ruleToc;
  Map<String, dynamic>? ruleContent;
  int? weight;

  LegadoSource({
    super.id,
    super.name,
    super.baseUrl,
    super.lang,
    super.isNsfw,
    super.iconUrl,
    super.version,
    super.versionLast,
    super.itemType,
    super.repo,
    super.hasUpdate,
    this.bookSourceName,
    this.bookSourceUrl,
    this.bookSourceGroup,
    this.bookSourceType,
    this.bookSourceComment,
    this.searchUrl,
    this.exploreUrl,
    this.header,
    this.ruleSearch,
    this.ruleExplore,
    this.ruleBookInfo,
    this.ruleToc,
    this.ruleContent,
    this.weight,
  });

  /// Legado sources have no stable id; derive one from url + name.
  static String generateId(String url, [String? name]) =>
      md5.convert(utf8.encode('$url|${name ?? ''}')).toString();

  factory LegadoSource.fromLegadoJson(
    Map<String, dynamic> json, {
    String? repoUrl,
  }) {
    final rawName = (json['bookSourceName'] ?? json['name'] ?? '').toString();
    final rawUrl = (json['bookSourceUrl'] ?? json['baseUrl'] ?? '').toString();
    final rawGroup =
        (json['bookSourceGroup'] ?? json['lang'] ?? '').toString();
    final sourceId = json['id']?.toString() ?? generateId(rawUrl, rawName);

    Map<String, dynamic>? parseRuleMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      if (value is String && value.trim().startsWith('{')) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
      return null;
    }

    String? headerStr;
    if (json['header'] != null) {
      if (json['header'] is String) {
        headerStr = json['header'] as String;
      } else {
        try {
          headerStr = jsonEncode(json['header']);
        } catch (_) {}
      }
    }

    final hasExplore = json['exploreUrl'] != null &&
        json['exploreUrl'].toString().trim().isNotEmpty;

    String? resolvedIcon;
    final rawIcon =
        (json['iconUrl'] ?? json['bookSourceIcon'])?.toString().trim();
    if (rawIcon != null && rawIcon.isNotEmpty) {
      if (rawIcon.startsWith('http://') || rawIcon.startsWith('https://')) {
        resolvedIcon = rawIcon;
      } else if (rawIcon.startsWith('//')) {
        resolvedIcon = 'https:$rawIcon';
      } else if (rawUrl.isNotEmpty) {
        try {
          resolvedIcon = Uri.parse(rawUrl).resolve(rawIcon).toString();
        } catch (_) {}
      }
    }
    if ((resolvedIcon == null || resolvedIcon.isEmpty) && rawUrl.isNotEmpty) {
      final host = Uri.tryParse(rawUrl)?.host;
      if (host != null && host.isNotEmpty) {
        resolvedIcon =
            'https://www.google.com/s2/favicons?domain=$host&sz=128';
      }
    }

    return LegadoSource(
      id: sourceId,
      name: rawName,
      baseUrl: rawUrl,
      lang: rawGroup.isNotEmpty ? rawGroup : 'all',
      isNsfw: false,
      iconUrl: resolvedIcon,
      version: json['version']?.toString() ?? '1.0.0',
      versionLast: json['versionLast']?.toString() ??
          json['lastUpdateTime']?.toString() ??
          '1.0.0',
      itemType: ItemType.novel,
      repo: repoUrl ?? json['repo']?.toString(),
      hasUpdate: false,
      bookSourceName: rawName,
      bookSourceUrl: rawUrl,
      bookSourceGroup: rawGroup,
      bookSourceType: json['bookSourceType'] is int
          ? json['bookSourceType'] as int
          : int.tryParse(json['bookSourceType']?.toString() ?? '0') ?? 0,
      bookSourceComment: json['bookSourceComment']?.toString(),
      searchUrl: json['searchUrl']?.toString(),
      exploreUrl: hasExplore ? json['exploreUrl'].toString() : null,
      header: headerStr,
      ruleSearch: parseRuleMap(json['ruleSearch']),
      ruleExplore: parseRuleMap(json['ruleExplore']),
      ruleBookInfo: parseRuleMap(json['ruleBookInfo']),
      ruleToc: parseRuleMap(json['ruleToc']),
      ruleContent: parseRuleMap(json['ruleContent']),
      weight: json['weight'] is int
          ? json['weight'] as int
          : int.tryParse(json['weight']?.toString() ?? ''),
    );
  }

  factory LegadoSource.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('bookSourceUrl') ||
        json.containsKey('bookSourceName') ||
        json.containsKey('ruleSearch')) {
      return LegadoSource.fromLegadoJson(json);
    }

    final base = Source.fromJson(json);
    Map<String, dynamic>? m(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : null;
    return LegadoSource(
      id: base.id,
      name: base.name,
      baseUrl: base.baseUrl,
      lang: base.lang,
      isNsfw: base.isNsfw,
      iconUrl: base.iconUrl,
      version: base.version,
      versionLast: base.versionLast,
      itemType: ItemType.novel,
      repo: base.repo,
      hasUpdate: base.hasUpdate,
      bookSourceName: json['bookSourceName']?.toString() ?? base.name,
      bookSourceUrl: json['bookSourceUrl']?.toString() ?? base.baseUrl,
      bookSourceGroup: json['bookSourceGroup']?.toString() ?? base.lang,
      bookSourceType: json['bookSourceType'] as int?,
      bookSourceComment: json['bookSourceComment']?.toString(),
      searchUrl: json['searchUrl']?.toString(),
      exploreUrl: json['exploreUrl']?.toString(),
      header: json['header']?.toString(),
      ruleSearch: m(json['ruleSearch']),
      ruleExplore: m(json['ruleExplore']),
      ruleBookInfo: m(json['ruleBookInfo']),
      ruleToc: m(json['ruleToc']),
      ruleContent: m(json['ruleContent']),
      weight: json['weight'] as int?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'bookSourceName': bookSourceName,
        'bookSourceUrl': bookSourceUrl,
        'bookSourceGroup': bookSourceGroup,
        'bookSourceType': bookSourceType,
        'bookSourceComment': bookSourceComment,
        'searchUrl': searchUrl,
        'exploreUrl': exploreUrl,
        'header': header,
        'ruleSearch': ruleSearch,
        'ruleExplore': ruleExplore,
        'ruleBookInfo': ruleBookInfo,
        'ruleToc': ruleToc,
        'ruleContent': ruleContent,
        'weight': weight,
      };
}
