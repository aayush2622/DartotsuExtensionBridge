import 'dart:convert';
import 'package:objectbox/objectbox.dart';

@Entity()
class BridgeSettings {
  @Id(assignable: true)
  int id;

  String? currentManager;

  // Internally store JSON
  String _sortedAnimeExtensionsJson;
  String _sortedMangaExtensionsJson;
  String _sortedNovelExtensionsJson;
  String _aniyomiAnimeExtensionsJson;
  String _aniyomiMangaExtensionsJson;
  String _mangayomiAnimeExtensionsJson;
  String _mangayomiMangaExtensionsJson;
  String _mangayomiNovelExtensionsJson;

  // Expose as List<String>
  List<String> get sortedAnimeExtensions =>
      List<String>.from(jsonDecode(_sortedAnimeExtensionsJson));
  set sortedAnimeExtensions(List<String> value) =>
      _sortedAnimeExtensionsJson = jsonEncode(value);

  List<String> get sortedMangaExtensions =>
      List<String>.from(jsonDecode(_sortedMangaExtensionsJson));
  set sortedMangaExtensions(List<String> value) =>
      _sortedMangaExtensionsJson = jsonEncode(value);

  List<String> get sortedNovelExtensions =>
      List<String>.from(jsonDecode(_sortedNovelExtensionsJson));
  set sortedNovelExtensions(List<String> value) =>
      _sortedNovelExtensionsJson = jsonEncode(value);

  List<String> get aniyomiAnimeExtensions =>
      List<String>.from(jsonDecode(_aniyomiAnimeExtensionsJson));
  set aniyomiAnimeExtensions(List<String> value) =>
      _aniyomiAnimeExtensionsJson = jsonEncode(value);

  List<String> get aniyomiMangaExtensions =>
      List<String>.from(jsonDecode(_aniyomiMangaExtensionsJson));
  set aniyomiMangaExtensions(List<String> value) =>
      _aniyomiMangaExtensionsJson = jsonEncode(value);

  List<String> get mangayomiAnimeExtensions =>
      List<String>.from(jsonDecode(_mangayomiAnimeExtensionsJson));
  set mangayomiAnimeExtensions(List<String> value) =>
      _mangayomiAnimeExtensionsJson = jsonEncode(value);

  List<String> get mangayomiMangaExtensions =>
      List<String>.from(jsonDecode(_mangayomiMangaExtensionsJson));
  set mangayomiMangaExtensions(List<String> value) =>
      _mangayomiMangaExtensionsJson = jsonEncode(value);

  List<String> get mangayomiNovelExtensions =>
      List<String>.from(jsonDecode(_mangayomiNovelExtensionsJson));
  set mangayomiNovelExtensions(List<String> value) =>
      _mangayomiNovelExtensionsJson = jsonEncode(value);

  BridgeSettings({
    this.id = 0,
    this.currentManager,
    List<String> sortedAnimeExtensions = const [],
    List<String> sortedMangaExtensions = const [],
    List<String> sortedNovelExtensions = const [],
    List<String> aniyomiAnimeExtensions = const [],
    List<String> aniyomiMangaExtensions = const [],
    List<String> mangayomiAnimeExtensions = const [],
    List<String> mangayomiMangaExtensions = const [],
    List<String> mangayomiNovelExtensions = const [],
  }) : _sortedAnimeExtensionsJson = jsonEncode(sortedAnimeExtensions),
       _sortedMangaExtensionsJson = jsonEncode(sortedMangaExtensions),
       _sortedNovelExtensionsJson = jsonEncode(sortedNovelExtensions),
       _aniyomiAnimeExtensionsJson = jsonEncode(aniyomiAnimeExtensions),
       _aniyomiMangaExtensionsJson = jsonEncode(aniyomiMangaExtensions),
       _mangayomiAnimeExtensionsJson = jsonEncode(mangayomiAnimeExtensions),
       _mangayomiMangaExtensionsJson = jsonEncode(mangayomiMangaExtensions),
       _mangayomiNovelExtensionsJson = jsonEncode(mangayomiNovelExtensions);
}
