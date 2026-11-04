import 'package:xml/xml.dart';

class DashUnsupported implements Exception {
  final String message;
  final bool needsFfmpeg;
  const DashUnsupported(this.message, {this.needsFfmpeg = false});

  @override
  String toString() => message;
}

class DashRepresentation {
  final String id;
  final String kind;
  final int bandwidth;
  final int? width;
  final int? height;
  final String? codecs;
  final String? language;
  final String? label;
  final Uri? init;
  final List<Uri> segments;
  final Uri? file;

  const DashRepresentation({
    required this.id,
    required this.kind,
    required this.bandwidth,
    this.width,
    this.height,
    this.codecs,
    this.language,
    this.label,
    this.init,
    this.segments = const [],
    this.file,
  });

  bool get isMuxed {
    final list = (codecs ?? '').toLowerCase().split(',');
    final audio = list.any(
      (c) =>
          c.startsWith('mp4a') || c.startsWith('ac-3') || c.startsWith('ec-3'),
    );
    final video = list.any(
      (c) =>
          c.startsWith('avc') ||
          c.startsWith('hev') ||
          c.startsWith('hvc') ||
          c.startsWith('av01') ||
          c.startsWith('vp'),
    );
    return audio && video;
  }

  String get quality {
    final kbps = bandwidth > 0 ? '${(bandwidth / 1000).round()} kbps' : null;
    if (height != null && height! > 0) {
      return kbps == null ? '${height}p' : '${height}p • $kbps';
    }
    return kbps ?? id;
  }

  String get audioLabel => label ?? language ?? id;
}

class DashManifest {
  final List<DashRepresentation> videos;
  final List<DashRepresentation> audios;
  final List<DashRepresentation> texts;
  final bool protected;

  const DashManifest({
    required this.videos,
    required this.audios,
    required this.texts,
    required this.protected,
  });
}

bool isDashManifest(String text) {
  final head = text.length > 2048 ? text.substring(0, 2048) : text;
  return head.contains('<MPD');
}

double? parseDashDuration(String? value) {
  if (value == null || value.isEmpty) return null;
  final match = RegExp(
    r'^P(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  double part(int i) => double.tryParse(match.group(i) ?? '') ?? 0;
  return part(1) * 86400 + part(2) * 3600 + part(3) * 60 + part(4);
}

String expandDashTemplate(
  String template, {
  required String id,
  required int bandwidth,
  int? number,
  int? time,
}) => template.replaceAllMapped(
  RegExp(r'\$(\$|RepresentationID|Number|Bandwidth|Time)(%0(\d+)d)?\$'),
  (m) {
    final key = m.group(1)!;
    if (key == r'$') return r'$';
    final width = int.tryParse(m.group(3) ?? '') ?? 0;
    final String text = switch (key) {
      'RepresentationID' => id,
      'Bandwidth' => '$bandwidth',
      'Number' => '${number ?? 0}',
      _ => '${time ?? 0}',
    };
    return key == 'RepresentationID' ? text : text.padLeft(width, '0');
  },
);

XmlElement? _child(XmlElement? parent, String name) {
  for (final e in parent?.childElements ?? const <XmlElement>[]) {
    if (e.name.local == name) return e;
  }
  return null;
}

Iterable<XmlElement> _children(XmlElement? parent, String name) =>
    parent?.childElements.where((e) => e.name.local == name) ??
    const Iterable.empty();

Uri _resolveBase(Uri parent, XmlElement element) {
  final text = _child(element, 'BaseURL')?.innerText.trim();
  if (text == null || text.isEmpty) return parent;
  return parent.resolve(text);
}

Map<String, String> _attrs(XmlElement? e) => {
  if (e != null)
    for (final a in e.attributes) a.name.local: a.value,
};

XmlElement? _inherit(List<XmlElement> chain, String name) {
  for (final e in chain) {
    final found = _child(e, name);
    if (found != null) return found;
  }
  return null;
}

DashManifest parseMpd(String text, Uri base) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text.replaceFirst('﻿', ''));
  } on XmlException catch (e) {
    throw DashUnsupported('Not a DASH manifest: ${e.message}');
  }
  final mpd = doc.rootElement;
  if (mpd.name.local != 'MPD') throw const DashUnsupported('Not an MPD');
  if (mpd.getAttribute('type') == 'dynamic') {
    throw const DashUnsupported('Live DASH streams cannot be downloaded');
  }
  final total = parseDashDuration(
    mpd.getAttribute('mediaPresentationDuration'),
  );
  final periods = _children(mpd, 'Period').toList();
  if (periods.isEmpty) {
    throw const DashUnsupported('DASH manifest has no period');
  }

  double lengthOf(XmlElement period) =>
      parseDashDuration(period.getAttribute('duration')) ??
      (periods.length == 1 ? total : null) ??
      0;
  final period = periods.reduce((a, b) => lengthOf(b) > lengthOf(a) ? b : a);
  final length = lengthOf(period);

  var protected = false;
  for (final cp in mpd.descendantElements.where(
    (e) => e.name.local == 'ContentProtection',
  )) {
    final scheme = (cp.getAttribute('schemeIdUri') ?? '').toLowerCase();
    if (scheme != 'urn:mpeg:dash:mp4protection:2011') protected = true;
  }

  final mpdBase = _resolveBase(base, mpd);
  final periodBase = _resolveBase(mpdBase, period);
  final videos = <DashRepresentation>[];
  final audios = <DashRepresentation>[];
  final texts = <DashRepresentation>[];

  for (final set in _children(period, 'AdaptationSet')) {
    final setBase = _resolveBase(periodBase, set);
    final setAttrs = _attrs(set);
    for (final rep in _children(set, 'Representation')) {
      final attrs = _attrs(rep);
      String? pick(String key) => attrs[key] ?? setAttrs[key];
      final mime = pick('mimeType') ?? '';
      final kind = switch ((pick('contentType') ?? mime.split('/').first)) {
        'video' => 'video',
        'audio' => 'audio',
        'text' || 'application' => 'text',
        _ => '',
      };
      if (kind.isEmpty) continue;
      final repBase = _resolveBase(setBase, rep);
      final id =
          attrs['id'] ?? '${videos.length + audios.length + texts.length}';
      final bandwidth = int.tryParse(attrs['bandwidth'] ?? '') ?? 0;
      final chain = [rep, set, period];
      Uri? init;
      var segments = <Uri>[];
      Uri? file;

      final template = _templateOf(chain);
      final list = _inherit(chain, 'SegmentList');
      if (template != null) {
        final media = template['media'];
        if (media == null) {
          throw const DashUnsupported('SegmentTemplate without media');
        }
        final scale = int.tryParse(template['timescale'] ?? '') ?? 1;
        final start = int.tryParse(template['startNumber'] ?? '') ?? 1;
        final initTemplate = template['initialization'];
        if (initTemplate != null) {
          init = repBase.resolve(
            expandDashTemplate(initTemplate, id: id, bandwidth: bandwidth),
          );
        }
        final timeline = _timelineOf(chain);
        Uri at(int number, int time) => repBase.resolve(
          expandDashTemplate(
            media,
            id: id,
            bandwidth: bandwidth,
            number: number,
            time: time,
          ),
        );
        if (timeline != null) {
          var number = start;
          var time = 0;
          for (final s in _children(timeline, 'S')) {
            final t = int.tryParse(s.getAttribute('t') ?? '');
            if (t != null) time = t;
            final d = int.tryParse(s.getAttribute('d') ?? '') ?? 0;
            if (d <= 0) throw const DashUnsupported('Invalid segment timeline');
            var repeat = int.tryParse(s.getAttribute('r') ?? '') ?? 0;
            if (repeat < 0) {
              final end = length * scale;
              repeat = ((end - time) / d).ceil() - 1;
              if (repeat < 0) repeat = 0;
            }
            for (var i = 0; i <= repeat; i++) {
              segments.add(at(number++, time));
              time += d;
            }
          }
        } else {
          final duration = int.tryParse(template['duration'] ?? '');
          if (duration == null || duration <= 0 || length <= 0) {
            throw const DashUnsupported('Cannot work out the segment count');
          }
          if (media.contains(r'$Time')) {
            throw const DashUnsupported('Time based template without timeline');
          }
          final count = (length * scale / duration).ceil();
          for (var i = 0; i < count; i++) {
            segments.add(at(start + i, i * duration));
          }
        }
      } else if (list != null) {
        final initNode = _child(list, 'Initialization');
        final source = initNode?.getAttribute('sourceURL');
        if (source != null) init = repBase.resolve(source);
        for (final s in _children(list, 'SegmentURL')) {
          final media = s.getAttribute('media');
          if (media == null) {
            segments = const [];
            file = repBase;
            break;
          }
          segments.add(repBase.resolve(media));
        }
        if (segments.isEmpty && file == null) file = repBase;
      } else {
        file = repBase;
      }

      if (file != null && file == base) continue;
      final language = pick('lang');
      final labelNode = _child(set, 'Label')?.innerText.trim();
      final entry = DashRepresentation(
        id: id,
        kind: kind,
        bandwidth: bandwidth,
        width: int.tryParse(attrs['width'] ?? setAttrs['width'] ?? ''),
        height: int.tryParse(attrs['height'] ?? setAttrs['height'] ?? ''),
        codecs: pick('codecs'),
        language: language,
        label: labelNode != null && labelNode.isNotEmpty ? labelNode : null,
        init: init,
        segments: segments,
        file: file,
      );
      switch (kind) {
        case 'video':
          videos.add(entry);
        case 'audio':
          audios.add(entry);
        default:
          texts.add(entry);
      }
    }
  }
  return DashManifest(
    videos: videos,
    audios: audios,
    texts: texts,
    protected: protected,
  );
}

Map<String, String>? _templateOf(List<XmlElement> chain) {
  final merged = <String, String>{};
  var found = false;
  for (final e in chain.reversed) {
    final t = _child(e, 'SegmentTemplate');
    if (t == null) continue;
    found = true;
    merged.addAll(_attrs(t));
  }
  return found ? merged : null;
}

XmlElement? _timelineOf(List<XmlElement> chain) {
  for (final e in chain) {
    final t = _child(e, 'SegmentTemplate');
    final timeline = _child(t, 'SegmentTimeline');
    if (timeline != null) return timeline;
  }
  return null;
}

DashRepresentation pickDashVideo(
  List<DashRepresentation> videos, {
  int? height,
}) {
  final sorted = [...videos]
    ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
  if (height == null) return sorted.first;
  DashRepresentation? best;
  var gap = 1 << 30;
  for (final v in sorted) {
    final h = v.height;
    if (h == null) continue;
    final d = (h - height).abs();
    if (d < gap) {
      gap = d;
      best = v;
    }
  }
  return best ?? sorted.first;
}

List<DashRepresentation> dashAudioOptions(List<DashRepresentation> audios) {
  final best = <String, DashRepresentation>{};
  for (final a in audios) {
    final key = '${a.language ?? ''}|${a.label ?? ''}'.toLowerCase();
    final known = best[key];
    if (known == null || a.bandwidth > known.bandwidth) best[key] = a;
  }
  return best.values.toList();
}

List<DashRepresentation> pickDashAudios(
  List<DashRepresentation> audios,
  List<String> labels,
) {
  final options = dashAudioOptions(audios);
  if (options.isEmpty) return const [];
  final out = <DashRepresentation>[];
  for (final label in labels) {
    final wanted = label.toLowerCase();
    final match = options
        .where(
          (a) =>
              a.audioLabel.toLowerCase() == wanted ||
              (a.language ?? '').toLowerCase() == wanted,
        )
        .firstOrNull;
    if (match != null && !out.contains(match)) out.add(match);
  }
  if (out.isEmpty) out.add(options.first);
  return out;
}
