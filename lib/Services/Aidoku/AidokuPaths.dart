import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'Postcard.dart';

typedef Pt = ({double x, double y});

class AidokuStroke {
  AidokuStroke({
    required this.color,
    required this.width,
    required this.cap,
    required this.join,
    required this.dash,
    required this.dashOffset,
  });

  final List<double> color;
  final double width;
  final int cap;
  final int join;
  final List<double> dash;
  final double dashOffset;
}

List<List<Pt>> decodeAidokuPath(Uint8List bytes) {
  final r = PostcardReader(bytes);
  final ops = r.readVarU();
  final subpaths = <List<Pt>>[];
  var current = <Pt>[];
  Pt at() => current.isEmpty ? (x: 0.0, y: 0.0) : current.last;
  Pt point() => (x: r.readF32(), y: r.readF32());
  void flush() {
    if (current.length > 1) subpaths.add(current);
    current = <Pt>[];
  }

  for (var i = 0; i < ops; i++) {
    switch (r.readVarU()) {
      case 0:
        flush();
        current.add(point());
      case 1:
        current.add(point());
      case 2:
        final c = point();
        final p = point();
        final s = at();
        for (var t = 1; t <= 12; t++) {
          final u = t / 12;
          final a = (1 - u) * (1 - u);
          final b = 2 * (1 - u) * u;
          final d = u * u;
          current.add((
            x: a * s.x + b * c.x + d * p.x,
            y: a * s.y + b * c.y + d * p.y,
          ));
        }
      case 3:
        final p = point();
        final c1 = point();
        final c2 = point();
        final s = at();
        for (var t = 1; t <= 16; t++) {
          final u = t / 16;
          final a = math.pow(1 - u, 3).toDouble();
          final b = 3 * math.pow(1 - u, 2) * u;
          final c = 3 * (1 - u) * u * u;
          final d = u * u * u;
          current.add((
            x: a * s.x + b * c1.x + c * c2.x + d * p.x,
            y: a * s.y + b * c1.y + c * c2.y + d * p.y,
          ));
        }
      case 4:
        final center = point();
        final radius = r.readF32();
        final start = r.readF32();
        final sweep = r.readF32();
        final steps = math.max(
          4,
          (sweep.abs() * radius / 2).ceil().clamp(4, 96),
        );
        for (var t = 0; t <= steps; t++) {
          final ang = start + sweep * t / steps;
          current.add((
            x: center.x + radius * math.cos(ang),
            y: center.y + radius * math.sin(ang),
          ));
        }
      case 5:
        if (current.isNotEmpty) current.add(current.first);
        flush();
      default:
        throw const FormatException('bad path op');
    }
  }
  flush();
  return subpaths;
}

AidokuStroke decodeAidokuStroke(Uint8List bytes) {
  final r = PostcardReader(bytes);
  final color = [r.readF32(), r.readF32(), r.readF32(), r.readF32()];
  final width = r.readF32();
  final cap = r.readVarU();
  final join = r.readVarU();
  r.readF32();
  final dash = r.readVec(r.readF32);
  final offset = r.readF32();
  return AidokuStroke(
    color: color,
    width: width,
    cap: cap,
    join: join,
    dash: dash,
    dashOffset: offset,
  );
}

class AidokuMask {
  AidokuMask(this.width, this.height) : data = Uint8List(width * height);

  final int width;
  final int height;
  final Uint8List data;

  void fillPolygons(List<List<Pt>> polys) {
    if (polys.isEmpty) return;
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in polys) {
      for (final v in p) {
        minY = math.min(minY, v.y);
        maxY = math.max(maxY, v.y);
      }
    }
    final y0 = math.max(0, minY.floor());
    final y1 = math.min(height - 1, maxY.ceil());
    const sub = 4;
    final cover = Float32List(width);
    for (var y = y0; y <= y1; y++) {
      cover.fillRange(0, width, 0);
      var touched = false;
      for (var s = 0; s < sub; s++) {
        final sy = y + (s + 0.5) / sub;
        final xs = <(double, int)>[];
        for (final poly in polys) {
          for (var i = 0; i < poly.length; i++) {
            final a = poly[i];
            final b = poly[(i + 1) % poly.length];
            if ((a.y <= sy && b.y > sy) || (b.y <= sy && a.y > sy)) {
              final t = (sy - a.y) / (b.y - a.y);
              xs.add((a.x + t * (b.x - a.x), b.y > a.y ? 1 : -1));
            }
          }
        }
        if (xs.isEmpty) continue;
        xs.sort((l, r) => l.$1.compareTo(r.$1));
        var winding = 0;
        for (var i = 0; i < xs.length - 1; i++) {
          winding += xs[i].$2;
          if (winding == 0) continue;
          final from = xs[i].$1.clamp(0, width.toDouble());
          final to = xs[i + 1].$1.clamp(0, width.toDouble());
          if (to <= from) continue;
          touched = true;
          final fx = from.floor();
          final tx = math.min(width - 1, to.floor());
          for (var x = fx; x <= tx; x++) {
            final l = math.max(from, x.toDouble());
            final h = math.min(to, x + 1.0);
            if (h > l) cover[x] += (h - l) / sub;
          }
        }
      }
      if (!touched) continue;
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final c = cover[x];
        if (c <= 0) continue;
        final v = (c * 255).round().clamp(0, 255);
        if (v > data[row + x]) data[row + x] = v;
      }
    }
  }

  void paint(img.Image image, List<double> rgba) {
    final scale = rgba.take(3).any((v) => v > 1) ? 1.0 : 255.0;
    final r = rgba[0] * scale, g = rgba[1] * scale, b = rgba[2] * scale;
    final alpha = rgba[3].clamp(0.0, 1.0);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final m = data[y * width + x];
        if (m == 0) continue;
        final a = m / 255 * alpha;
        final px = image.getPixel(x, y);
        final da = px.a / 255;
        final oa = a + da * (1 - a);
        if (oa <= 0) continue;
        double mix(num s, num d) => (s * a + d * da * (1 - a)) / oa;
        px
          ..r = mix(r, px.r)
          ..g = mix(g, px.g)
          ..b = mix(b, px.b)
          ..a = oa * 255;
      }
    }
  }
}

List<Pt> transformPoints(
  List<Pt> points,
  double tx,
  double ty,
  double sx,
  double sy,
  double rotation,
) {
  final c = math.cos(rotation), s = math.sin(rotation);
  return [
    for (final p in points)
      (
        x: tx + (p.x * sx) * c - (p.y * sy) * s,
        y: ty + (p.x * sx) * s + (p.y * sy) * c,
      ),
  ];
}

List<List<Pt>> strokeToPolygons(List<List<Pt>> subpaths, AidokuStroke style) {
  final half = math.max(style.width, 0.1) / 2;
  final out = <List<Pt>>[];
  final pieces = <List<Pt>>[];
  for (final path in subpaths) {
    if (style.dash.isEmpty || style.dash.every((d) => d <= 0)) {
      pieces.add(path);
    } else {
      pieces.addAll(_dash(path, style.dash, style.dashOffset));
    }
  }
  for (final path in pieces) {
    for (var i = 0; i < path.length - 1; i++) {
      final a = path[i], b = path[i + 1];
      var dx = b.x - a.x, dy = b.y - a.y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len == 0) continue;
      dx /= len;
      dy /= len;
      var ax = a.x, ay = a.y, bx = b.x, by = b.y;
      if (style.cap == 1 && (i == 0 || i == path.length - 2)) {
        if (i == 0) {
          ax -= dx * half;
          ay -= dy * half;
        }
        if (i == path.length - 2) {
          bx += dx * half;
          by += dy * half;
        }
      }
      final nx = -dy * half, ny = dx * half;
      out.add([
        (x: ax + nx, y: ay + ny),
        (x: bx + nx, y: by + ny),
        (x: bx - nx, y: by - ny),
        (x: ax - nx, y: ay - ny),
      ]);
    }
    if (style.join == 0 || style.cap == 0) {
      final ends = <Pt>[
        if (style.cap == 0) ...[path.first, path.last],
        if (style.join == 0) ...path.sublist(1, path.length - 1),
      ];
      for (final p in ends) {
        out.add(_circle(p, half));
      }
    }
  }
  return out;
}

List<Pt> _circle(Pt c, double r) {
  final steps = math.max(8, (r * 4).ceil().clamp(8, 48));
  return [
    for (var i = 0; i < steps; i++)
      (
        x: c.x + r * math.cos(2 * math.pi * i / steps),
        y: c.y + r * math.sin(2 * math.pi * i / steps),
      ),
  ];
}

List<List<Pt>> _dash(List<Pt> path, List<double> pattern, double offset) {
  final out = <List<Pt>>[];
  final total = pattern.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return [path];
  var idx = 0;
  var left = pattern[0];
  var phase = offset % (total * (pattern.length.isOdd ? 2 : 1));
  while (phase > 0) {
    if (phase >= left) {
      phase -= left;
      idx = (idx + 1) % pattern.length;
      left = pattern[idx];
    } else {
      left -= phase;
      phase = 0;
    }
  }
  var on = idx.isEven;
  var cur = <Pt>[if (on) path.first];
  for (var i = 0; i < path.length - 1; i++) {
    var a = path[i];
    final b = path[i + 1];
    var dx = b.x - a.x, dy = b.y - a.y;
    var seg = math.sqrt(dx * dx + dy * dy);
    if (seg == 0) continue;
    dx /= seg;
    dy /= seg;
    while (seg > left) {
      a = (x: a.x + dx * left, y: a.y + dy * left);
      seg -= left;
      if (on) {
        cur.add(a);
        out.add(cur);
        cur = <Pt>[];
      } else {
        cur = <Pt>[a];
      }
      on = !on;
      idx = (idx + 1) % pattern.length;
      left = pattern[idx] <= 0 ? 0.01 : pattern[idx];
    }
    left -= seg;
    if (on) cur.add(b);
  }
  if (on && cur.length > 1) out.add(cur);
  return out;
}
