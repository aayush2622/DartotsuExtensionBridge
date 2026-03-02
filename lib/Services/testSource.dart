import '../Extensions/SourceMethods.dart';
import '../Models/DEpisode.dart';
import '../Models/DMedia.dart';
import '../Models/Page.dart';
import '../Models/Pages.dart';
import '../Models/Source.dart';
import '../Models/SourcePreference.dart';
import '../Models/Video.dart';

class TestSource extends Source implements SourceMethods {
  TestSource()
      : super(
          id: 'test',
          name: 'Test Source',
          baseUrl: 'https://example.com',
          lang: 'en',
          itemType: ItemType.manga,
        );

  @override
  Source get source => this;
  @override
  Future<DMedia> getDetail(DMedia media) async {
    throw UnimplementedError();
  }

  @override
  Future<Pages> getLatestUpdates(int page) async {
    throw UnimplementedError();
  }

  @override
  Future<String?> getNovelContent(
    String chapterTitle,
    String chapterId,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) async {
    throw UnimplementedError();
  }

  @override
  Future<Pages> getPopular(int page) async {
    throw UnimplementedError();
  }

  @override
  Future<List<SourcePreference>> getPreference() async {
    return [];
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async {
    return [];
  }

  @override
  Future<Pages> search(
    String query,
    int page,
    List<dynamic> filters,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> setPreference(SourcePreference pref, value) async {
    return true;
  }
}
