import 'package:dartotsu_extension_bridge/toolkit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('titleRatio ignores case, punctuation and word order', () {
    expect(titleRatio('Attack on Titan', 'attack on titan!'), 100);
    expect(titleRatio('Titan Attack', 'Attack Titan') >= 90, isTrue);
    expect(titleRatio('One Piece', 'Bleach') < 50, isTrue);
  });

  test('languageMatcher knows codes, names and native names', () {
    final es = languageMatcher('es')!;
    expect(es.matches(language: 'spa'), isTrue);
    expect(es.matches(title: 'Español'), isTrue);
    expect(es.matches(language: 'en'), isFalse);
    expect(languageList('ja, en ,'), ['ja', 'en']);
  });

  test('pickTrack follows the priority list and avoids signs', () {
    final tracks = [('Signs & Songs', 'en'), ('Full', 'en'), ('日本語', 'ja')];
    String? pick(List<String> priority, {bool avoid = false}) => pickTrack(
      tracks,
      priority,
      language: (t) => t.$2,
      title: (t) => t.$1,
      avoidSigns: avoid,
    )?.$1;
    expect(pick(['en']), 'Signs & Songs');
    expect(pick(['en'], avoid: true), 'Full');
    expect(pick(['ja', 'en']), '日本語');
    expect(pick(['fr']), isNull);
  });

  test('episodeNumberOf reads common release names', () {
    expect(episodeNumberOf('[Group] Show - 05 [1080p].mkv'), 5);
    expect(episodeNumberOf('Show S01E12.mkv'), 12);
    expect(episodeNumberOf('Ep 7.mp4'), 7);
  });

  test('HLS master playlists list variants by height', () {
    const text = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720
high.m3u8
''';
    expect(isMasterPlaylist(text), isTrue);
    final variants = parseMaster(
      text,
      Uri.parse('https://x.test/a/master.m3u8'),
    );
    expect(variants.map((v) => v.height), [360, 720]);
    expect(variants.last.uri.toString(), 'https://x.test/a/high.m3u8');
  });
}
