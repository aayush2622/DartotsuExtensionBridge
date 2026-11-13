import 'package:dartotsu_extension_bridge/Player/Video/NativeVideoController.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hd = Size(1920, 1080);

  test('a 4K video in a 1080p view renders at the view size', () {
    expect(fittedRenderSize(3840, 2160, [(hd, BoxFit.contain)]), (1920, 1080));
  });

  test('a video smaller than the view is never upscaled', () {
    expect(fittedRenderSize(1280, 720, [(hd, BoxFit.contain)]), (1280, 720));
  });

  test('a reduction under 15 % is skipped', () {
    expect(fittedRenderSize(2100, 1180, [(hd, BoxFit.contain)]), (2100, 1180));
  });

  test('cover needs the larger scale, contain the smaller', () {
    const tall = Size(1080, 1280);
    expect(fittedRenderSize(3840, 2160, [(tall, BoxFit.contain)]), (1080, 608));
    expect(fittedRenderSize(3840, 2160, [(tall, BoxFit.cover)]), (2276, 1280));
  });

  test('several views get the largest of their needs', () {
    expect(
      fittedRenderSize(3840, 2160, [
        (const Size(640, 360), BoxFit.contain),
        (hd, BoxFit.contain),
      ]),
      (1920, 1080),
    );
  });

  test('without views nothing changes', () {
    expect(fittedRenderSize(3840, 2160, const []), (3840, 2160));
  });
}
