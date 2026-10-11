import '../Eval/dart/model/m_chapter.dart';
import '../Eval/dart/model/m_manga.dart';
import '../Eval/dart/model/m_pages.dart';
import '../Eval/dart/model/page.dart';
import '../Eval/dart/model/source_preference.dart';
import '../Eval/dart/model/video.dart';

/// Plain-JSON forms of the interpreter results, used to move them between the
/// worker and the main isolate. The models' own `toJson`s aren't a faithful
/// round trip (`MManga.toJson` writes `status` as a name that `fromJson`
/// can't read back), so the transport has its own.

Map<String, dynamic> encodeMManga(MManga m) => {
  'name': m.name,
  'link': m.link,
  'imageUrl': m.imageUrl,
  'description': m.description,
  'author': m.author,
  'artist': m.artist,
  'status': m.status?.index,
  'genre': m.genre,
  'chapters': m.chapters?.map((c) => c.toJson()).toList(),
};

MManga decodeMManga(Map json) {
  final statusIndex = json['status'] as int?;
  return MManga(
    name: json['name'] as String?,
    link: json['link'] as String?,
    imageUrl: json['imageUrl'] as String?,
    description: json['description'] as String?,
    author: json['author'] as String?,
    artist: json['artist'] as String?,
    status: statusIndex == null ? Status.unknown : Status.values[statusIndex],
    genre: (json['genre'] as List?)?.cast<String>(),
    chapters: (json['chapters'] as List?)
        ?.map((c) => MChapter.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList(),
  );
}

Map<String, dynamic> encodeMPages(MPages p) => {
  'hasNextPage': p.hasNextPage,
  'list': p.list.map(encodeMManga).toList(),
};

MPages decodeMPages(Map json) => MPages(
  list: (json['list'] as List).map((e) => decodeMManga(e as Map)).toList(),
  hasNextPage: json['hasNextPage'] as bool? ?? false,
);

List<Map<String, dynamic>> encodePageUrls(List<PageUrl> pages) =>
    pages.map((p) => p.toJson()).toList();

List<PageUrl> decodePageUrls(List json) => json
    .map((e) => PageUrl.fromJson(Map<String, dynamic>.from(e as Map)))
    .toList();

List<Map<String, dynamic>> encodeVideos(List<Video> videos) =>
    videos.map((v) => v.toJson()).toList();

List<Video> decodeVideos(List json) => json
    .map((e) => Video.fromJson(Map<String, dynamic>.from(e as Map)))
    .toList();

List<Map<String, dynamic>> encodePreferences(List<SourcePreference> prefs) =>
    prefs.map((p) => p.toJson()).toList();

List<SourcePreference> decodePreferences(List json) => json
    .map(
      (e) => SourcePreference.fromJson(Map<String, dynamic>.from(e as Map)),
    )
    .toList();
