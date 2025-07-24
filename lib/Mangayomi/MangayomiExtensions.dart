import 'package:dartotsu_extension_bridge/Extensions/Extensions.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:get/get.dart';

import 'MangayomiExtensionManager.dart';
import 'Models/Source.dart';

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
    checkForUpdates(ItemType.anime);
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
    checkForUpdates(ItemType.manga);
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
    checkForUpdates(ItemType.novel);
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
  Future<void> uninstallSource(Source source) async {
    final manager = Get.put(MangayomiExtensionManager());

    if (source.id == null || source.id!.isEmpty) {
      return Future.error('Source ID is required for uninstallation.');
    }

    await manager.uninstallSource(source);

    // put back into available extensions if repo has the source
    void updateExtensions(
      Rx<List<Source>> extensions,
      List<MSource> availableSources,
    ) {
      final availableMap = {for (var s in availableSources) s.id: s};
      final idInt = int.tryParse(source.id!);
      if (idInt != null && availableMap.containsKey(idInt)) {
        extensions.value = extensions.value..add(source);
      }
    }

    switch (source.itemType!) {
      case ItemType.anime:
        updateExtensions(
          availableAnimeExtensions,
          manager.availableAnimeExtensions.value,
        );
        break;
      case ItemType.manga:
        updateExtensions(
          availableMangaExtensions,
          manager.availableMangaExtensions.value,
        );
        break;
      case ItemType.novel:
        updateExtensions(
          availableNovelExtensions,
          manager.availableNovelExtensions.value,
        );
        break;
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    final manager = Get.put(MangayomiExtensionManager());
    if (source.id == null || source.id!.isEmpty) {
      return Future.error('Source ID is required for update.');
    }
    await manager.updateSource(source);
  }

  Future<void> checkForUpdates(ItemType type) async {
    final manager = Get.put(MangayomiExtensionManager());

    List<MSource> availableList;
    Rx<List<Source>> installedRx;

    switch (type) {
      case ItemType.anime:
        availableList = manager.availableAnimeExtensions.value;
        installedRx = installedAnimeExtensions;
        break;
      case ItemType.manga:
        availableList = manager.availableMangaExtensions.value;
        installedRx = installedMangaExtensions;
        break;
      case ItemType.novel:
        availableList = manager.availableNovelExtensions.value;
        installedRx = installedNovelExtensions;
        break;
    }

    final availableMap = {for (var source in availableList) source.id: source};

    final updatedList = installedRx.value.map((installed) {
      final available = availableMap[int.tryParse(installed.id ?? '')];
      if (available != null &&
          installed.version != null &&
          available.version != null &&
          compareVersions(installed.version!, available.version!) < 0) {
        return installed
          ..hasUpdate = true
          ..versionLast = available.version;
      }
      return installed;
    }).toList();

    installedRx.value = updatedList;
  }
}

int compareVersions(String version1, String version2) {
  List<String> v1Components = version1.split('.');
  List<String> v2Components = version2.split('.');

  for (int i = 0; i < v1Components.length && i < v2Components.length; i++) {
    int v1Value = int.parse(
      v1Components.length == i + 1 && v1Components[i].length == 1
          ? "${v1Components[i]}0"
          : v1Components[i],
    );
    int v2Value = int.parse(
      v2Components.length == i + 1 && v2Components[i].length == 1
          ? "${v2Components[i]}0"
          : v2Components[i],
    );

    if (v1Value < v2Value) {
      return -1;
    } else if (v1Value > v2Value) {
      return 1;
    }
  }

  if (v1Components.length < v2Components.length) {
    return -1;
  } else if (v1Components.length > v2Components.length) {
    return 1;
  }

  return 0;
}
