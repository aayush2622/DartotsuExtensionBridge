import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'AidokuPaths.dart';

class AidokuImage {
  AidokuImage(this.image);

  final img.Image image;
}

class AidokuCanvas {
  AidokuCanvas(this.image);

  final img.Image image;
  double translateX = 0;
  double translateY = 0;
  double scaleX = 1;
  double scaleY = 1;
  double rotation = 0;

  void fillPaths(List<List<Pt>> paths, List<double> rgba) {
    final mask = AidokuMask(image.width, image.height);
    mask.fillPolygons([
      for (final p in paths)
        transformPoints(p, translateX, translateY, scaleX, scaleY, rotation),
    ]);
    mask.paint(image, rgba);
  }

  void strokePaths(List<List<Pt>> paths, AidokuStroke style) {
    final moved = [
      for (final p in paths)
        transformPoints(p, translateX, translateY, scaleX, scaleY, rotation),
    ];
    final mask = AidokuMask(image.width, image.height);
    mask.fillPolygons(strokeToPolygons(moved, style));
    mask.paint(image, style.color);
  }

  void text(String value, double size, double x, double y, List<double> rgba) {
    final font = size <= 18
        ? img.arial14
        : size <= 36
        ? img.arial24
        : img.arial48;
    final scale = rgba.take(3).any((v) => v > 1) ? 1.0 : 255.0;
    img.drawString(
      image,
      value,
      font: font,
      x: (translateX + x * scaleX).round(),
      y: (translateY + y * scaleY).round(),
      color: img.ColorRgba8(
        (rgba[0] * scale).round().clamp(0, 255),
        (rgba[1] * scale).round().clamp(0, 255),
        (rgba[2] * scale).round().clamp(0, 255),
        (rgba[3] * 255).round().clamp(0, 255),
      ),
    );
  }

  static AidokuCanvas? create(double width, double height) {
    final w = width.ceil();
    final h = height.ceil();
    if (w <= 0 || h <= 0 || w * h > 100000000) return null;
    return AidokuCanvas(img.Image(width: w, height: h, numChannels: 4));
  }

  int draw(
    img.Image source, {
    required double srcX,
    required double srcY,
    required double srcWidth,
    required double srcHeight,
    required double dstX,
    required double dstY,
    required double dstWidth,
    required double dstHeight,
  }) {
    final sx = srcX.round();
    final sy = srcY.round();
    final sw = (srcX + srcWidth).round() - sx;
    final sh = (srcY + srcHeight).round() - sy;
    if (sw <= 0 ||
        sh <= 0 ||
        sx < 0 ||
        sy < 0 ||
        sx + sw > source.width ||
        sy + sh > source.height) {
      return -4;
    }
    final left = translateX + dstX * scaleX;
    final top = translateY + dstY * scaleY;
    final dx = left.round();
    final dy = top.round();
    final dw = (left + dstWidth * scaleX).round() - dx;
    final dh = (top + dstHeight * scaleY).round() - dy;
    if (dw <= 0 || dh <= 0) return -6;
    var piece = sx == 0 && sy == 0 && sw == source.width && sh == source.height
        ? source
        : img.copyCrop(source, x: sx, y: sy, width: sw, height: sh);
    if (piece.width != dw || piece.height != dh) {
      piece = img.copyResize(
        piece,
        width: dw,
        height: dh,
        interpolation: dw < piece.width
            ? img.Interpolation.average
            : img.Interpolation.linear,
      );
    }
    if (piece.numChannels != 4) piece = piece.convert(numChannels: 4);
    img.compositeImage(
      image,
      piece,
      dstX: dx,
      dstY: dy,
      blend: img.BlendMode.alpha,
    );
    return 0;
  }
}

img.Image? decodeAidokuImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return decoded.numChannels == 4 ? decoded : decoded.convert(numChannels: 4);
}

Uint8List encodeAidokuImage(img.Image image) =>
    Uint8List.fromList(img.encodePng(image, level: 1));
