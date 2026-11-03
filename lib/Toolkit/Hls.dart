class HlsUnsupported implements Exception {
  final String message;
  const HlsUnsupported(this.message);

  @override
  String toString() => message;
}

class HlsVariant {
  final Uri uri;
  final int bandwidth;
  final int? width;
  final int? height;
  final String? audioGroup;

  const HlsVariant(
    this.uri,
    this.bandwidth,
    this.width,
    this.height, {
    this.audioGroup,
  });

  String get label {
    final kbps = bandwidth > 0 ? '${(bandwidth / 1000).round()} kbps' : null;
    if (height != null && height! > 0) {
      return kbps == null ? '${height}p' : '${height}p • $kbps';
    }
    return kbps ?? uri.pathSegments.lastOrNull ?? uri.toString();
  }
}

class HlsAudio {
  final Uri? uri;
  final String name;
  final String? language;
  final String group;
  final bool isDefault;

  const HlsAudio(
    this.uri,
    this.name,
    this.language,
    this.group,
    this.isDefault,
  );

  String get label => name.isNotEmpty ? name : (language ?? group);
}

class HlsKey {
  final Uri? uri;
  final String? iv;

  const HlsKey(this.uri, this.iv);

  @override
  bool operator ==(Object other) =>
      other is HlsKey && other.uri == uri && other.iv == iv;

  @override
  int get hashCode => Object.hash(uri, iv);
}

class HlsSegment {
  final Uri uri;
  final double duration;
  final HlsKey? key;
  final Uri? map;

  const HlsSegment(this.uri, this.duration, this.key, this.map);
}

class HlsMedia {
  final int sequence;
  final int target;
  final List<HlsSegment> segments;

  const HlsMedia(this.sequence, this.target, this.segments);

  double get duration => segments.fold(0, (sum, s) => sum + s.duration);
}

bool isMasterPlaylist(String text) => text.contains('#EXT-X-STREAM-INF');

Map<String, String> _attributes(String line) {
  final out = <String, String>{};
  final body = line.substring(line.indexOf(':') + 1);
  final pattern = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
  for (final m in pattern.allMatches(body)) {
    var value = m.group(2)!;
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1);
    }
    out[m.group(1)!] = value;
  }
  return out;
}

List<String> _lines(String text) => [
  for (final raw in text.split(RegExp(r'\r?\n')))
    if (raw.trim().isNotEmpty) raw.trim(),
];

List<HlsVariant> parseMaster(String text, Uri base) {
  final lines = _lines(text);
  final out = <HlsVariant>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
    final attrs = _attributes(line);
    var j = i + 1;
    while (j < lines.length && lines[j].startsWith('#')) {
      j++;
    }
    if (j >= lines.length) break;
    final size = (attrs['RESOLUTION'] ?? '').split('x');
    out.add(
      HlsVariant(
        base.resolve(lines[j]),
        int.tryParse(attrs['BANDWIDTH'] ?? attrs['AVERAGE-BANDWIDTH'] ?? '') ??
            0,
        size.length == 2 ? int.tryParse(size[0]) : null,
        size.length == 2 ? int.tryParse(size[1]) : null,
        audioGroup: attrs['AUDIO'],
      ),
    );
  }
  return out;
}

List<HlsAudio> parseAudios(String text, Uri base) {
  final out = <HlsAudio>[];
  for (final line in _lines(text)) {
    if (!line.startsWith('#EXT-X-MEDIA')) continue;
    final attrs = _attributes(line);
    if ((attrs['TYPE'] ?? '').toUpperCase() != 'AUDIO') continue;
    final uri = attrs['URI'];
    out.add(
      HlsAudio(
        uri == null || uri.isEmpty ? null : base.resolve(uri),
        attrs['NAME'] ?? '',
        attrs['LANGUAGE'],
        attrs['GROUP-ID'] ?? '',
        (attrs['DEFAULT'] ?? '').toUpperCase() == 'YES',
      ),
    );
  }
  return out;
}

List<HlsAudio> audiosFor(List<HlsAudio> audios, HlsVariant? variant) {
  final group = variant?.audioGroup;
  final own = [
    for (final a in audios)
      if (a.uri != null && (group == null || a.group == group)) a,
  ];
  final seen = <String>{};
  return [
    for (final a in own)
      if (seen.add('${a.label.toLowerCase()}|${a.uri}')) a,
  ];
}

HlsAudio? pickAudio(List<HlsAudio> audios, HlsVariant? variant, String? label) {
  final options = audiosFor(audios, variant);
  if (options.isEmpty) return null;
  final wanted = label?.toLowerCase();
  if (wanted != null) {
    for (final a in options) {
      if (a.label.toLowerCase() == wanted) return a;
    }
  }
  return options.firstWhere((a) => a.isDefault, orElse: () => options.first);
}

HlsVariant pickVariant(List<HlsVariant> variants, {int? height}) {
  final sorted = [...variants]
    ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
  if (height == null) return sorted.first;
  HlsVariant? best;
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

HlsMedia parseMedia(String text, Uri base) {
  final lines = _lines(text);
  var sequence = 0;
  var target = 0;
  HlsKey? key;
  Uri? map;
  double? duration;
  final segments = <HlsSegment>[];
  for (final line in lines) {
    if (line.startsWith('#EXT-X-MEDIA-SEQUENCE')) {
      sequence = int.tryParse(line.split(':').last) ?? 0;
    } else if (line.startsWith('#EXT-X-TARGETDURATION')) {
      target = int.tryParse(line.split(':').last) ?? 0;
    } else if (line.startsWith('#EXT-X-KEY')) {
      final attrs = _attributes(line);
      final method = (attrs['METHOD'] ?? 'NONE').toUpperCase();
      if (method == 'NONE') {
        key = null;
      } else if (method == 'AES-128') {
        final uri = attrs['URI'];
        if (uri == null) throw const HlsUnsupported('Encrypted without a key');
        key = HlsKey(base.resolve(uri), attrs['IV']);
      } else {
        throw HlsUnsupported('Unsupported encryption ($method)');
      }
    } else if (line.startsWith('#EXT-X-MAP')) {
      final attrs = _attributes(line);
      if (attrs.containsKey('BYTERANGE')) {
        throw const HlsUnsupported('Byte range playlists are not supported');
      }
      final uri = attrs['URI'];
      map = uri == null ? null : base.resolve(uri);
    } else if (line.startsWith('#EXT-X-BYTERANGE')) {
      throw const HlsUnsupported('Byte range playlists are not supported');
    } else if (line.startsWith('#EXTINF')) {
      duration = double.tryParse(line.substring(8).split(',').first.trim());
    } else if (!line.startsWith('#')) {
      segments.add(HlsSegment(base.resolve(line), duration ?? 0, key, map));
      duration = null;
    }
  }
  if (segments.isEmpty) {
    throw const HlsUnsupported('The playlist has no segments');
  }
  return HlsMedia(sequence, target, segments);
}

String hlsExtension(Uri uri, {String fallback = 'ts'}) {
  final name = uri.pathSegments.lastOrNull ?? '';
  final dot = name.lastIndexOf('.');
  if (dot < 0) return fallback;
  final ext = name.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : fallback;
}

const hlsAllowedExtensions = {
  '3gp',
  'aac',
  'avi',
  'ac3',
  'eac3',
  'flac',
  'mkv',
  'm4a',
  'm4s',
  'm4v',
  'mpg',
  'mov',
  'mp2',
  'mp3',
  'mp4',
  'mpeg',
  'mpegts',
  'ogg',
  'ogv',
  'oga',
  'ts',
  'vob',
  'vtt',
  'wav',
  'webvtt',
};

String segmentName(int index, Uri uri) {
  final ext = hlsExtension(uri);
  final safe = hlsAllowedExtensions.contains(ext) ? ext : 'ts';
  return 'seg${index.toString().padLeft(5, '0')}.$safe';
}

String buildLocalPlaylist(
  HlsMedia media, {
  required String Function(Uri uri) keyName,
  required String Function(Uri uri) mapName,
}) {
  final out = StringBuffer('#EXTM3U\n#EXT-X-VERSION:7\n');
  out.writeln(
    '#EXT-X-TARGETDURATION:${media.target > 0 ? media.target : media.segments.map((s) => s.duration.ceil()).reduce((a, b) => a > b ? a : b)}',
  );
  out.writeln('#EXT-X-MEDIA-SEQUENCE:${media.sequence}');
  out.writeln('#EXT-X-PLAYLIST-TYPE:VOD');
  HlsKey? key;
  Uri? map;
  var wroteKey = false;
  for (final (i, s) in media.segments.indexed) {
    if (!wroteKey || s.key != key) {
      wroteKey = true;
      key = s.key;
      if (key == null) {
        out.writeln('#EXT-X-KEY:METHOD=NONE');
      } else {
        final iv = key.iv == null ? '' : ',IV=${key.iv}';
        out.writeln('#EXT-X-KEY:METHOD=AES-128,URI="${keyName(key.uri!)}"$iv');
      }
    }
    if (s.map != map) {
      map = s.map;
      if (map != null) out.writeln('#EXT-X-MAP:URI="${mapName(map)}"');
    }
    out.writeln('#EXTINF:${s.duration.toStringAsFixed(6)},');
    out.writeln(segmentName(i, s.uri));
  }
  out.writeln('#EXT-X-ENDLIST');
  return out.toString();
}

String buildLocalMaster({
  required HlsAudio audio,
  required String audioPath,
  required String videoPath,
}) {
  final language = audio.language == null
      ? ''
      : ',LANGUAGE="${audio.language}"';
  return '#EXTM3U\n'
      '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="${audio.label.replaceAll('"', "'")}"$language,DEFAULT=YES,AUTOSELECT=YES,URI="$audioPath"\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=1,AUDIO="audio"\n'
      '$videoPath\n';
}
