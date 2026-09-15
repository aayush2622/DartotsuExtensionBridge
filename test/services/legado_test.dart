import 'dart:convert';

import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Services/Legado/Models/LegadoSource.dart';
import 'package:dartotsu_extension_bridge/Services/Legado/RuleEngine/LegadoRuleEngine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LegadoSource.fromLegadoJson', () {
    test('maps the core 书源 fields and derives a stable id', () {
      final s = LegadoSource.fromLegadoJson({
        'bookSourceName': '测试书源',
        'bookSourceUrl': 'https://example.com',
        'bookSourceGroup': '轻小说',
        'bookSourceType': 0,
        'searchUrl': '/search?q={{key}}<,&page={{page}}>',
        'exploreUrl': 'Hot::/rank/hot\nLatest::/rank/new',
        'ruleSearch': {
          'bookList': '.book',
          'name': 'h3@text',
          'bookUrl': 'a@href',
        },
        'ruleContent': {'content': '#content@text'},
      }, repoUrl: 'https://repo/x.json');

      expect(s.name, '测试书源');
      expect(s.baseUrl, 'https://example.com');
      expect(s.lang, '轻小说');
      expect(s.itemType, ItemType.novel);
      expect(s.repo, 'https://repo/x.json');
      expect(s.exploreUrl, contains('Hot::'));
      expect(s.ruleSearch!['bookList'], '.book');
      expect(s.id, LegadoSource.generateId('https://example.com', '测试书源'));
      expect(s.id!.length, 32); // md5 hex
    });

    test('parses rule maps given as JSON strings', () {
      final s = LegadoSource.fromLegadoJson({
        'bookSourceUrl': 'https://x',
        'ruleToc':
            '{"chapterList":"ul li","chapterName":"a@text","chapterUrl":"a@href"}',
      });
      expect(s.ruleToc, isA<Map<String, dynamic>>());
      expect(s.ruleToc!['chapterList'], 'ul li');
    });

    test('exploreUrl is null when absent (no popular/latest support)', () {
      final s = LegadoSource.fromLegadoJson({'bookSourceUrl': 'https://x'});
      expect(s.exploreUrl, isNull);
    });

    test('survives a JSON round-trip through the base Source shape', () {
      final s = LegadoSource.fromLegadoJson({
        'bookSourceName': 'RT',
        'bookSourceUrl': 'https://rt.example',
        'ruleSearch': {'bookList': '.b'},
      });
      final back = LegadoSource.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back.id, s.id);
      expect(back.bookSourceUrl, 'https://rt.example');
      expect(back.ruleSearch!['bookList'], '.b');
      expect(back.itemType, ItemType.novel);
    });
  });

  group('LegadoRuleEngine', () {
    const html = '''
      <html><body>
        <ul class="list">
          <li><a href="/book/1">First Book</a><span class="author">Alice</span></li>
          <li><a href="/book/2">Second Book</a><span class="author">Bob</span></li>
        </ul>
        <div id="content"><p>line one</p><p>line two</p><p>广告 remove me</p></div>
        <a class="next" href="/chapter/2">next page</a>
      </body></html>
    ''';

    test('selectElements + extractString pull list rows and fields', () {
      final doc = LegadoRuleEngine.parseHtml(html);
      final rows = LegadoRuleEngine.selectElements(doc, '.list li');
      expect(rows, hasLength(2));

      final title = LegadoRuleEngine.extractString(rows.first, 'a@text');
      final url = LegadoRuleEngine.extractString(
        rows.first,
        'a@href',
        baseUrl: 'https://site.example/x/',
      );
      final author = LegadoRuleEngine.extractString(rows.first, '.author@text');
      expect(title, 'First Book');
      expect(url, 'https://site.example/book/1');
      expect(author, 'Alice');
    });

    test('|| falls through to the next selector, ## applies a regex strip', () {
      final doc = LegadoRuleEngine.parseHtml(html);
      final missing = LegadoRuleEngine.extractString(
        doc,
        '.nope@text || .list li:first-child a@text',
      );
      expect(missing, 'First Book');

      final content = LegadoRuleEngine.extractString(
        doc,
        '#content p@text##广告.*',
      );
      expect(content, contains('line one'));
      expect(content, isNot(contains('广告')));
    });

    test('buildUrl handles {{key}} / {{page}} and <…{{page}}…> sections', () {
      final p1 = LegadoRuleEngine.buildUrl(
        urlTemplate: '/search?q={{key}}<&page={{page}}>',
        baseUrl: 'https://s.example',
        query: 'hello world',
        page: 1,
      );
      final p3 = LegadoRuleEngine.buildUrl(
        urlTemplate: '/search?q={{key}}<&page={{page}}>',
        baseUrl: 'https://s.example',
        query: 'hello world',
        page: 3,
      );
      expect(p1, 'https://s.example/search?q=hello%20world');
      expect(p3, 'https://s.example/search?q=hello%20world&page=3');
    });
  });
}
