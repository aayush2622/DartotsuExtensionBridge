import 'dart:io';

import 'package:dartotsu_extension_bridge/Engines/Ffmpeg/FfmpegAddon.dart'
    show FfmpegCancel;
import 'package:dartotsu_extension_bridge/downloads.dart';
import 'package:dartotsu_extension_bridge/toolkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  test('duration based templates give the right segment count and urls', () {
    final m = parseMpd(
      _fixture('dash_bbb.mpd'),
      Uri.parse('https://cdn.test/a/stream.mpd'),
    );
    expect(m.protected, isFalse);
    expect(m.videos.length, 10);
    final small = m.videos.firstWhere(
      (v) => v.height == 180 && v.bandwidth < 300000,
    );
    expect(small.segments.length, (634.566 * 30 / 120).ceil());
    expect(
      small.init.toString(),
      'https://cdn.test/a/bbb_30fps_320x180_200k/bbb_30fps_320x180_200k_0.m4v',
    );
    expect(
      small.segments.first.toString(),
      'https://cdn.test/a/bbb_30fps_320x180_200k/bbb_30fps_320x180_200k_1.m4v',
    );
    expect(m.audios, isNotEmpty);
    expect(m.audios.first.segments.length, (634.566 * 48000 / 192512).ceil());
  });

  test('single file representations are one download', () {
    final m = parseMpd(
      _fixture('dash_shaka.mpd'),
      Uri.parse('https://cdn.test/s/dash.mpd'),
    );
    expect(m.videos, isNotEmpty);
    expect(m.videos.every((v) => v.file != null && v.segments.isEmpty), isTrue);
    expect(m.videos.first.file.toString(), startsWith('https://cdn.test/s/'));
    expect(m.texts, isNotEmpty);
  });

  test('segment timelines expand repeats and open ended repeats', () {
    const mpd = '''<MPD type="static" mediaPresentationDuration="PT20S">
<Period><AdaptationSet mimeType="video/mp4">
<SegmentTemplate timescale="1000" media="v/\$Number%03d\$-\$Time\$.m4s" initialization="v/init.mp4" startNumber="5">
<SegmentTimeline><S t="0" d="4000" r="1"/><S d="2000"/><S d="5000" r="-1"/></SegmentTimeline>
</SegmentTemplate>
<Representation id="r1" bandwidth="1000" codecs="avc1.4d401e,mp4a.40.2" width="640" height="360"/>
</AdaptationSet></Period></MPD>''';
    final r = parseMpd(mpd, Uri.parse('https://x/y/m.mpd')).videos.single;
    expect(r.isMuxed, isTrue);
    expect(r.segments.map((u) => u.pathSegments.last).toList(), [
      '005-0.m4s',
      '006-4000.m4s',
      '007-8000.m4s',
      '008-10000.m4s',
      '009-15000.m4s',
    ]);
    expect(r.init.toString(), 'https://x/y/v/init.mp4');
  });

  test('segment lists, base urls and period selection', () {
    const mpd = '''<MPD type="static" mediaPresentationDuration="PT100S">
<BaseURL>https://cdn.test/root/</BaseURL>
<Period duration="PT10S"><AdaptationSet mimeType="video/mp4"><Representation id="ad" bandwidth="1" codecs="avc1"><BaseURL>ad.mp4</BaseURL></Representation></AdaptationSet></Period>
<Period duration="PT90S"><AdaptationSet mimeType="video/mp4"><Representation id="main" bandwidth="5" height="720" codecs="avc1"><BaseURL>main/</BaseURL>
<SegmentList><Initialization sourceURL="i.mp4"/><SegmentURL media="a.m4s"/><SegmentURL media="b.m4s"/></SegmentList>
</Representation></AdaptationSet></Period></MPD>''';
    final r = parseMpd(mpd, Uri.parse('https://x/m.mpd')).videos.single;
    expect(r.id, 'main');
    expect(r.init.toString(), 'https://cdn.test/root/main/i.mp4');
    expect(r.segments.map((u) => u.toString()).toList(), [
      'https://cdn.test/root/main/a.m4s',
      'https://cdn.test/root/main/b.m4s',
    ]);
  });

  test('live and protected streams are refused', () async {
    expect(
      () => parseMpd('<MPD type="dynamic"/>', Uri.parse('https://x/m.mpd')),
      throwsA(isA<DashUnsupported>()),
    );
    const drm =
        '''<MPD type="static" mediaPresentationDuration="PT4S"><Period><AdaptationSet mimeType="video/mp4">
<ContentProtection schemeIdUri="urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed"/>
<SegmentTemplate duration="2" media="s\$Number\$.m4s" initialization="i.mp4"/>
<Representation id="1" bandwidth="1" codecs="avc1"/></AdaptationSet></Period></MPD>''';
    expect(parseMpd(drm, Uri.parse('https://x/m.mpd')).protected, isTrue);
    final temp = await Directory.systemTemp.createTemp('dash_drm');
    addTearDown(() => temp.delete(recursive: true));
    await expectLater(
      downloadDash(
        url: 'https://x/m.mpd',
        output: File(p.join(temp.path, 'e.mp4')),
        ffmpeg: null,
        cancel: DownloadCancel(),
        ffmpegCancel: FfmpegCancel(),
        onProgress: (_, _) {},
        onFinishing: () {},
        getText: (_) async => drm,
      ),
      throwsA(isA<DashUnsupported>()),
    );
  });

  test('quality and audio picking', () {
    final m = parseMpd(
      _fixture('dash_envivio.mpd'),
      Uri.parse('https://x/e.mpd'),
    );
    expect(
      pickDashVideo(m.videos).bandwidth,
      m.videos.map((v) => v.bandwidth).reduce((a, b) => a > b ? a : b),
    );
    expect(pickDashVideo(m.videos, height: 180).height, 180);
    expect(pickDashAudios(m.audios, const ['nope']).length, 1);
  });

  test('a muxed single representation downloads and joins in order', () async {
    const mpd =
        '''<MPD type="static" mediaPresentationDuration="PT6S"><Period><AdaptationSet mimeType="video/mp4">
<SegmentTemplate duration="2" timescale="1" media="s\$Number\$.m4s" initialization="init.mp4"/>
<Representation id="1" bandwidth="1" codecs="avc1.4d401e,mp4a.40.2"/></AdaptationSet></Period></MPD>''';
    final temp = await Directory.systemTemp.createTemp('dash_dl');
    addTearDown(() => temp.delete(recursive: true));
    final output = File(p.join(temp.path, 'e.mp4'));
    final progress = <int>[];
    await downloadDash(
      url: 'https://x/m.mpd',
      output: output,
      ffmpeg: null,
      cancel: DownloadCancel(),
      ffmpegCancel: FfmpegCancel(),
      onProgress: (done, total) => progress.add(done * 100 ~/ total),
      onFinishing: () {},
      getText: (_) async => mpd,
      getFile: (uri, target) =>
          target.writeAsString(uri.pathSegments.last, flush: true),
    );
    expect(await output.readAsString(), 'init.mp4s1.m4ss2.m4ss3.m4s');
    expect(progress.last, 100);
    expect(Directory(p.join(temp.path, '.e')).existsSync(), isFalse);
  });
}
