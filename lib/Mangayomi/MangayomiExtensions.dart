import 'package:dartotsu_extension_bridge/Extensions/Extensions.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:get/get.dart';

import 'MangayomiExtensionManager.dart';

class MangayomiExtensions extends Extension {
  MangayomiExtensions() {
    initialize();
  }

  @override
  Future<List<Source>> fetchAvailableAnimeExtensions(
    List<String>? repos,
  ) async {
    final manager = Get.put(MangayomiExtensionManager());

    final sources = await manager.fetchAvailableExtensionsStream(
      ItemType.anime,
      repos,
    );
    var idMap = installedAnimeExtensions.value
        .map((source) => source.id)
        .toSet();
    final sourceList = sources
        .map((source) => Source.fromJson(source.toJson()))
        .where((source) => !idMap.contains(source.id))
        .toList();
    availableAnimeExtensions.value = sourceList;
    return sourceList;
  }

  @override
  Future<List<Source>> getInstalledAnimeExtensions() async {
    final manager = Get.put(MangayomiExtensionManager());

    final stream = manager
        .getExtensionsStream(ItemType.anime)
        .map(
          (sources) => sources
              .map((source) => Source.fromJson(source.toJson()))
              .toList(),
        )
        .asBroadcastStream();

    installedAnimeExtensions.bindStream(stream);

    return await stream.first;
  }

  @override
  Future<List<Source>> fetchAvailableMangaExtensions(
    List<String>? repos,
  ) async {
    final manager = Get.put(MangayomiExtensionManager());

    final sources = await manager.fetchAvailableExtensionsStream(
      ItemType.manga,
      repos,
    );
    var idMap = installedMangaExtensions.value
        .map((source) => source.id)
        .toSet();
    final sourceList = sources
        .map((source) => Source.fromJson(source.toJson()))
        .where((source) => !idMap.contains(source.id))
        .toList();
    availableMangaExtensions.value = sourceList;
    return sourceList;
  }

  @override
  Future<List<Source>> getInstalledMangaExtensions() async {
    final manager = Get.put(MangayomiExtensionManager());

    final stream = manager
        .getExtensionsStream(ItemType.manga)
        .map(
          (sources) => sources
              .map((source) => Source.fromJson(source.toJson()))
              .toList(),
        )
        .asBroadcastStream();
    installedMangaExtensions.bindStream(stream);

    return await stream.first;
  }

  @override
  Future<List<Source>> fetchAvailableNovelExtensions(
    List<String>? repos,
  ) async {
    final manager = Get.put(MangayomiExtensionManager());

    final sources = await manager.fetchAvailableExtensionsStream(
      ItemType.novel,
      repos,
    );
    var idMap = installedNovelExtensions.value
        .map((source) => source.id)
        .toSet();
    final sourceList = sources
        .map((source) => Source.fromJson(source.toJson()))
        .where((source) => !idMap.contains(source.id))
        .toList();
    availableNovelExtensions.value = sourceList;
    return sourceList;
  }

  @override
  Future<List<Source>> getInstalledNovelExtensions() {
    final manager = Get.put(MangayomiExtensionManager());

    final stream = manager
        .getExtensionsStream(ItemType.novel)
        .map(
          (sources) => sources
              .map((source) => Source.fromJson(source.toJson()))
              .toList(),
        )
        .asBroadcastStream();

    installedNovelExtensions.bindStream(stream);

    return stream.first;
  }

  @override
  Future<void> initialize() async {
    if (!isInitialized.value) {
      isInitialized.value = true;
      getInstalledAnimeExtensions();
      getInstalledMangaExtensions();
      getInstalledNovelExtensions();
      fetchAvailableAnimeExtensions([
        'https://kodjodevf.github.io/mangayomi-extensions/anime_index.json',
      ]);
      fetchAvailableMangaExtensions(null);
      fetchAvailableNovelExtensions(null);
    }
  }

  @override
  Future<void> installSource(Source source) async {
    final manager = Get.put(MangayomiExtensionManager());
    if (source.id == null || source.id!.isEmpty) {
      return Future.error('Source ID is required for installation.');
    }

    await manager.installSource(source);

    switch (source.itemType!) {
      case ItemType.anime:
        availableAnimeExtensions.value = availableAnimeExtensions.value
            .where((s) => s.id != source.id)
            .toList();
        break;
      case ItemType.manga:
        availableMangaExtensions.value = availableMangaExtensions.value
            .where((s) => s.id != source.id)
            .toList();
        break;
      case ItemType.novel:
        availableNovelExtensions.value = availableNovelExtensions.value
            .where((s) => s.id != source.id)
            .toList();
        break;
    }
  }

  @override
  Future<void> uninstallSource(Source source) {
    // TODO: implement uninstallSource
    throw UnimplementedError();
  }

  @override
  Future<void> updateSource(Source source) {
    // TODO: implement updateSource
    throw UnimplementedError();
  }
}
