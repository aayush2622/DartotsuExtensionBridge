class Video {
  String? title;
  String url;
  String quality;
  Map<String, String>? headers;
  List<Track>? subtitles;
  List<Track>? audios;
  List<TimeStamp>? timeStamps;
  Video(
    this.title,
    this.url,
    this.quality, {
    this.headers,
    this.subtitles,
    this.audios,
    this.timeStamps,
  });

  factory Video.fromJson(Map<String, dynamic> json) {
    // A video without a url is unusable - fail clearly here rather than
    // letting `null.toString()` silently produce the 4-character string
    // "null" as the url, which then fails much later (an HTTP request to a
    // bogus path) instead of at the point the bad data was actually seen.
    // Callers building a list from several of these (parseVideos) catch
    // this and skip just the one malformed entry.
    final url = json['url'];
    if (url == null) {
      throw FormatException('Video JSON is missing a "url" field: $json');
    }

    return Video(
      json['title']?.toString().trim(),
      url.toString().trim(),
      json['quality']?.toString().trim() ?? '',
      headers: (json['headers'] as Map?)?.cast<String, String>(),
      subtitles: _parseTracks(json['subtitles']),
      audios: _parseTracks(json['audios']),
      timeStamps: _parseTimeStamps(json['timeStamps']),
    );
  }

  static List<Track> _parseTracks(dynamic value) {
    if (value is! List) return [];

    final tracks = <Track>[];
    for (final e in value) {
      if (e == null) continue;
      try {
        tracks.add(Track.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {
        // One malformed subtitle/audio track entry should not drop the
        // whole video.
      }
    }
    return tracks;
  }

  static List<TimeStamp> _parseTimeStamps(dynamic value) {
    if (value is! List) return [];

    final stamps = <TimeStamp>[];
    for (final e in value) {
      if (e == null) continue;
      try {
        stamps.add(TimeStamp.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {
        // One malformed timestamp (e.g. a non-numeric startTime) should not
        // drop the whole video - this used to throw straight out of
        // Video.fromJson and take the entire video list down with it.
      }
    }
    return stamps;
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'quality': quality,
    'headers': headers,
    'subtitles': subtitles?.map((e) => e.toJson()).toList(),
    'audios': audios?.map((e) => e.toJson()).toList(),
    'timeStamps': timeStamps?.map((e) => e.toJson()).toList(),
  };
}

class TimeStamp {
  String? name;
  double startTime;
  double endTime;

  TimeStamp({this.name, required this.startTime, required this.endTime});

  factory TimeStamp.fromJson(Map<String, dynamic> json) {
    return TimeStamp(
      name: json['name']?.toString(),
      startTime: (json['startTime'] as num).toDouble(),
      endTime: (json['endTime'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'startTime': startTime,
    'endTime': endTime,
  };
}

class Track {
  String? file;
  String? label;

  Track({this.file, this.label});

  Track.fromJson(Map<String, dynamic> json) {
    file = json['file']?.toString().trim();
    label = json['label']?.toString().trim();
  }

  Map<String, dynamic> toJson() => {'file': file, 'label': label};
}
