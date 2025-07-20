import 'package:dartotsu_extension_bridge/Models/DMedia.dart';
import 'package:dartotsu_extension_bridge/Models/Page.dart';

import '../Models/DEpisode.dart';
import '../Models/Pages.dart';
import '../Models/Source.dart';
import '../Models/Video.dart';

abstract class SourceMethods {
  late Source source;

  Future<Pages> getPopular(int page);

  Future<Pages> getLatestUpdates(int page);

  Future<Pages> search(String query, int page, List<dynamic> filters);

  Future<DMedia> getDetail(DMedia media);

  Future<List<PageUrl>> getPageList(DEpisode episode);

  Future<List<Video>> getVideoList(DEpisode episode);
}
