import 'dart:io';

import 'package:dartotsu_extension_bridge/Engines/Ffmpeg/FfmpegAddon.dart'
    show FfmpegCancel;
import 'package:dartotsu_extension_bridge/downloads.dart';
import 'package:dartotsu_extension_bridge/toolkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _master = '''#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="Japanese",LANGUAGE="ja",DEFAULT=YES,URI="ja.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="English",LANGUAGE="en",DEFAULT=NO,URI="en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=1280x720,AUDIO="a"
video.m3u8
''';

String _media(String prefix) =>
    '#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4.0,\n${prefix}0.ts\n#EXTINF:4.0,\n${prefix}1.ts\n#EXT-X-ENDLIST\n';

void main() {
  test('pickAudios returns each wanted rendition once', () {
    final audios = parseAudios(_master, Uri.parse('https://x/m.m3u8'));
    final variant = parseMaster(_master, Uri.parse('https://x/m.m3u8')).first;
    final both = pickAudios(audios, variant, [
      'english',
      'Japanese',
      'english',
    ]);
    expect(both.map((a) => a.label), ['English', 'Japanese']);
    expect(pickAudios(audios, variant, ['Klingon']).map((a) => a.label), [
      'Japanese',
    ]);
    expect(pickAudios(audios, variant, const []).length, 1);
  });

  test('a folder download keeps every chosen audio track', () async {
    final temp = await Directory.systemTemp.createTemp('hls_audio');
    addTearDown(() => temp.delete(recursive: true));
    final texts = {
      'https://x/m.m3u8': _master,
      'https://x/video.m3u8': _media('v'),
      'https://x/ja.m3u8': _media('j'),
      'https://x/en.m3u8': _media('e'),
    };
    await downloadHls(
      url: 'https://x/m.m3u8',
      output: File(p.join(temp.path, 'ep.mp4')),
      ffmpeg: null,
      cancel: DownloadCancel(),
      ffmpegCancel: FfmpegCancel(),
      onProgress: (_, _) {},
      onFinishing: () {},
      audioLabels: ['Japanese', 'English'],
      getText: (url) async => texts[url]!,
      getFile: (uri, target) => target.writeAsString('x'),
    );
    final master = await File(
      p.join(temp.path, 'ep', 'index.m3u8'),
    ).readAsString();
    expect(master, contains('NAME="Japanese"'));
    expect(master, contains('NAME="English"'));
    expect(master, contains('URI="audio0/audio.m3u8"'));
    expect(master, contains('URI="audio1/audio.m3u8"'));
    expect(
      File(p.join(temp.path, 'ep', 'audio1', 'audio.m3u8')).existsSync(),
      isTrue,
    );
  });
}
