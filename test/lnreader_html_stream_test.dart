import 'package:dartotsu_extension_bridge/Services/LnReader/Js/HtmlStream.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> run(String source) {
  final stream = HtmlStream();
  final events = [...stream.write(source), ...stream.end()];
  return [
    for (final e in events)
      switch (e[0]) {
        't' => 't:${e[1]}',
        'o' =>
          'o:${e[1]}${(e[2] as Map).entries.map((a) => ' ${a.key}=${a.value}').join()}',
        'c' => 'c:${e[1]}${e[2] == true ? '*' : ''}',
        _ => 'm:${e[1]}',
      },
  ];
}

void main() {
  test('apostrophes in text do not swallow the tags after them', () {
    expect(run("<p>Don't stop</p><div class=\"a\">x</div>"), [
      'o:p',
      "t:Don't stop",
      'c:p',
      'o:div class=a',
      't:x',
      'c:div',
    ]);
  });

  test('names are lowercased and entities decoded', () {
    expect(run('<A HREF="/x?a=1&amp;b=2">Tom &amp; Jerry</A>'), [
      'o:a href=/x?a=1&b=2',
      't:Tom & Jerry',
      'c:a',
    ]);
  });

  test('void elements close at once and open tags close at the end', () {
    expect(run('<div><br><img src=a.jpg><span>t'), [
      'o:div',
      'o:br',
      'c:br*',
      'o:img src=a.jpg',
      'c:img*',
      'o:span',
      't:t',
      'c:span*',
      'c:div*',
    ]);
  });

  test('a new list item or paragraph closes the previous one', () {
    expect(run('<ul><li>a<li>b</ul><p>x<p>y'), [
      'o:ul',
      'o:li',
      't:a',
      'c:li*',
      'o:li',
      't:b',
      'c:li*',
      'c:ul',
      'o:p',
      't:x',
      'c:p*',
      'o:p',
      't:y',
      'c:p*',
    ]);
  });

  test('closing a tag closes what is still open inside it', () {
    expect(run('<div><b><i>x</div>'), [
      'o:div',
      'o:b',
      'o:i',
      't:x',
      'c:i*',
      'c:b*',
      'c:div',
    ]);
  });

  test('stray closing tags are ignored', () {
    expect(run('a</span>b'), ['t:a', 't:b']);
  });

  test('script and style content is raw text', () {
    expect(run('<script>if (a < b && c) { x("</p>"); }</script><p>k</p>'), [
      'o:script',
      't:if (a < b && c) { x("</p>"); }',
      'c:script',
      'o:p',
      't:k',
      'c:p',
    ]);
  });

  test('comments and doctype produce no text', () {
    expect(run('<!DOCTYPE html><!-- hi --><p>x</p>'), [
      'm: hi ',
      'o:p',
      't:x',
      'c:p',
    ]);
  });

  test('a tag split across writes is held until it is complete', () {
    final stream = HtmlStream();
    final events = [
      ...stream.write('<div cla'),
      ...stream.write('ss="a">x</di'),
      ...stream.write('v>'),
      ...stream.end(),
    ];
    expect(events.map((e) => e[0]).toList(), ['o', 't', 'c']);
  });
}
