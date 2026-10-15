import 'package:dartotsu_extension_bridge/Services/Aidoku/AidokuSelector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as parser;

void main() {
  final doc = parser.parse('''
<ul class="info">
  <li>Author: <span class="v">Oda</span></li>
  <li>狀態：<span class="v">Ongoing</span></li>
  <li><a href="/x">Tags</a></li>
</ul>
<div class="a"><p>one</p></div><div class="b"><p>two</p></div>''');

  test('contains and descendants', () {
    final r = aidokuSelectAll(doc, 'li:contains(狀態：) > span.v');
    expect(r.single.text, 'Ongoing');
  });

  test('containsOwn, has, eq, groups', () {
    expect(aidokuSelectAll(doc, 'li:containsOwn(Author)').length, 1);
    expect(aidokuSelectAll(doc, 'li:has(a)').single.text, 'Tags');
    expect(aidokuSelectAll(doc, 'li:has(> span.v)').length, 2);
    expect(aidokuSelectAll(doc, 'li:eq(2)').single.text, 'Tags');
    expect(
      aidokuSelectAll(doc, 'div:has(p:contains(two)), li:eq(0)').length,
      2,
    );
    expect(needsAidokuSelector('div.a > p'), isFalse);
  });
}
