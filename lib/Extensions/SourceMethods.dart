import '../Models/DEpisode.dart';
import '../Models/DMedia.dart';
import '../Models/Page.dart';
import '../Models/Pages.dart';
import '../Models/Source.dart';
import '../Models/SourcePreference.dart';
import '../Models/Video.dart';

abstract class SourceMethods {
  Source get source;

  Future<Pages> getPopular(int page);

  Future<Pages> getLatestUpdates(int page);

  Future<Pages> search(String query, int page, List<dynamic> filters);

  Future<DMedia> getDetail(DMedia media);

  Future<List<PageUrl>> getPageList(DEpisode episode);

  Future<List<Video>> getVideoList(DEpisode episode);

  Future<String?> getNovelContent(DEpisode episode);

  Future<List<SourcePreference>> getPreference();

  Future<bool> setPreference(SourcePreference pref, dynamic value);
}

List<PageUrl> pagesWithHeaders(
  List<PageUrl> pages, {
  String? baseUrl,
  Map<String, String> headers = const {},
}) {
  final origin = _originOf(baseUrl);
  if (origin == null && headers.isEmpty) return pages;
  return [
    for (final page in pages)
      PageUrl(
        page.url,
        headers: _merged(origin, headers, page.headers),
        process: page.process,
      ),
  ];
}

Map<String, String>? _merged(
  String? origin,
  Map<String, String> shared,
  Map<String, String>? own,
) {
  final out = {...shared, ...?own};
  if (origin != null && !out.keys.any((k) => k.toLowerCase() == 'referer')) {
    out['Referer'] = origin;
  }
  return out.isEmpty ? null : out;
}

String? _originOf(String? baseUrl) {
  if (baseUrl == null || baseUrl.isEmpty) return null;
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/';
}
