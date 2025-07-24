import 'package:isar/isar.dart';
part 'Settings.g.dart';

@collection
@Name("BridgeSettings")
class BridgeSettings {
  Id? id;

  List<String> sortedAnimeExtensions;
  List<String> sortedMangaExtensions;
  List<String> sortedNovelExtensions;

  BridgeSettings({
    this.sortedAnimeExtensions = const [],
    this.sortedMangaExtensions = const [],
    this.sortedNovelExtensions = const [],
  });
}
