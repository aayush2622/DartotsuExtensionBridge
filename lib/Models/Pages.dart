import 'DMedia.dart';

class Pages {
  List<DMedia> list;
  bool hasNextPage;

  Pages({required this.list, this.hasNextPage = false});

  factory Pages.fromJson(Map<String, dynamic> json) {
    return Pages(
      list: _parseList(json['list']),
      hasNextPage: json['hasNextPage'] ?? false,
    );
  }

  static List<DMedia> _parseList(dynamic value) {
    if (value is! List) return [];

    final list = <DMedia>[];
    for (final e in value) {
      if (e == null) continue;
      try {
        list.add(DMedia.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {
        // One malformed search/listing result should not take down the
        // whole page of results.
      }
    }
    return list;
  }

  Map<String, dynamic> toJson() => {
    'list': list.map((v) => v.toJson()).toList(),
    'hasNextPage': hasNextPage,
  };
}
