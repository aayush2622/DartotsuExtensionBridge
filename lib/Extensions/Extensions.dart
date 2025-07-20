import 'package:get/get.dart';

import '../Models/Source.dart';

abstract class Extension extends GetxController {
  var isInitialized = false.obs;

  final Rx<List<Source>> installedAnimeExtensions = Rx([]);
  final Rx<List<Source>> installedMangaExtensions = Rx([]);
  final Rx<List<Source>> installedNovelExtensions = Rx([]);
  final Rx<List<Source>> availableAnimeExtensions = Rx([]);
  final Rx<List<Source>> availableMangaExtensions = Rx([]);
  final Rx<List<Source>> availableNovelExtensions = Rx([]);

  Future<List<Source>> getInstalledAnimeExtensions() => Future.value([]);

  Future<List<Source>> fetchAvailableAnimeExtensions(List<String>? repos) =>
      Future.value([]);

  Future<List<Source>> getInstalledMangaExtensions() => Future.value([]);

  Future<List<Source>> fetchAvailableMangaExtensions(List<String>? repos) =>
      Future.value([]);

  Future<List<Source>> getInstalledNovelExtensions() => Future.value([]);

  Future<List<Source>> fetchAvailableNovelExtensions(List<String>? repos) =>
      Future.value([]);
}
