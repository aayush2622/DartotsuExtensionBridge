import 'package:dartotsu_extension_bridge/Settings/Settings.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:get/get.dart';

import 'MangayomiExtensionManager.dart';
import 'Models/Source.dart';

class MangayomiExtensions extends Extension {
  MangayomiExtensions() {
    initialize();
  }

  final _manager = Get.put(MangayomiExtensionManager());

  @override
  Future<void> initialize() async {
    if (isInitialized.value) return;
    isInitialized.value = true;

    final settings = isar.bridgeSettings.getSync(26)!;

    await Future.wait([
      getInstalledAnimeExtensions(),
      getInstalledMangaExtensions(),
      getInstalledNovelExtensions(),
      fetchAvailableAnimeExtensions(settings.mangayomiAnimeExtensions),
      fetchAvailableMangaExtensions(settings.mangayomiMangaExtensions),
      fetchAvailableNovelExtensions(settings.mangayomiNovelExtensions),
    ]);
  }

  @override
  Future<List<Source>> fetchAvailableAnimeExtensions(List<String>? repos) =>
      _fetchAvailable(ItemType.anime, repos);

  @override
  Future<List<Source>> fetchAvailableMangaExtensions(List<String>? repos) =>
      _fetchAvailable(ItemType.manga, repos);

  @override
  Future<List<Source>> fetchAvailableNovelExtensions(List<String>? repos) =>
      _fetchAvailable(ItemType.novel, repos);

  Future<List<Source>> _fetchAvailable(
    ItemType type,
    List<String>? repos,
  ) async {
    final settings = isar.bridgeSettings.getSync(26)!;
    isar.writeTxnSync(() {
      switch (type) {
        case ItemType.anime:
          settings.mangayomiAnimeExtensions = repos ?? [];
          break;
        case ItemType.manga:
          settings.mangayomiMangaExtensions = repos ?? [];
          break;
        case ItemType.novel:
          settings.mangayomiNovelExtensions = repos ?? [];
          break;
      }
      isar.writeTxnSync(() => isar.bridgeSettings.putSync(settings));
    });

    final sources = await _manager.fetchAvailableExtensionsStream(type, repos);
    final installedIds = _getInstalledRx(type).value.map((e) => e.id).toSet();

    final list = sources
        .map((e) => Source.fromJson(e.toJson(), ExtensionType.mangayomi))
        .where((s) => !installedIds.contains(s.id))
        .toList();

    _getAvailableRx(type).value = list;
    checkForUpdates(type);
    return list;
  }

  @override
  Future<List<Source>> getInstalledAnimeExtensions() =>
      _getInstalled(ItemType.anime);

  @override
  Future<List<Source>> getInstalledMangaExtensions() =>
      _getInstalled(ItemType.manga);

  @override
  Future<List<Source>> getInstalledNovelExtensions() =>
      _getInstalled(ItemType.novel);

  Future<List<Source>> _getInstalled(ItemType type) async {
    final stream = _manager
        .getExtensionsStream(type)
        .map(
          (sources) => sources
              .map((s) => Source.fromJson(s.toJson(), ExtensionType.mangayomi))
              .toList(),
        )
        .asBroadcastStream();

    _getInstalledRx(type).bindStream(stream);
    return stream.first;
  }

  @override
  Future<void> installSource(Source source) async {
    if (source.id?.isEmpty ?? true) {
      return Future.error('Source ID is required for installation.');
    }

    await _manager.installSource(source);

    final rx = _getAvailableRx(source.itemType!);
    rx.value = rx.value.where((s) => s.id != source.id).toList();
  }

  @override
  Future<void> uninstallSource(Source source) async {
    if (source.id?.isEmpty ?? true) {
      return Future.error('Source ID is required for uninstallation.');
    }

    await _manager.uninstallSource(source);

    final availableList = _getAvailableList(source.itemType!);
    final idInt = int.tryParse(source.id ?? '');
    if (idInt != null && availableList.any((s) => s.id == idInt)) {
      _getAvailableRx(source.itemType!).update((list) => list?.add(source));
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    if (source.id?.isEmpty ?? true) {
      return Future.error('Source ID is required for update.');
    }
    await _manager.updateSource(source);
  }

  Future<void> checkForUpdates(ItemType type) async {
    final availableMap = {for (var s in _getAvailableList(type)) s.id: s};

    final updated = _getInstalledRx(type).value.map((installed) {
      final avail = availableMap[int.tryParse(installed.id ?? '')];
      if (avail != null &&
          installed.version != null &&
          avail.version != null &&
          _compareVersions(installed.version!, avail.version!) < 0) {
        return installed
          ..hasUpdate = true
          ..versionLast = avail.version;
      }
      return installed;
    }).toList();

    _getInstalledRx(type).value = updated;
  }

  Rx<List<Source>> _getAvailableRx(ItemType type) {
    switch (type) {
      case ItemType.anime:
        return availableAnimeExtensions;
      case ItemType.manga:
        return availableMangaExtensions;
      case ItemType.novel:
        return availableNovelExtensions;
    }
  }

  Rx<List<Source>> _getInstalledRx(ItemType type) {
    switch (type) {
      case ItemType.anime:
        return installedAnimeExtensions;
      case ItemType.manga:
        return installedMangaExtensions;
      case ItemType.novel:
        return installedNovelExtensions;
    }
  }

  List<MSource> _getAvailableList(ItemType type) {
    switch (type) {
      case ItemType.anime:
        return _manager.availableAnimeExtensions.value;
      case ItemType.manga:
        return _manager.availableMangaExtensions.value;
      case ItemType.novel:
        return _manager.availableNovelExtensions.value;
    }
  }

  int _compareVersions(String v1, String v2) {
    final a = v1.split('.').map(int.tryParse).toList();
    final b = v2.split('.').map(int.tryParse).toList();

    for (int i = 0; i < a.length || i < b.length; i++) {
      final n1 = i < a.length ? a[i] ?? 0 : 0;
      final n2 = i < b.length ? b[i] ?? 0 : 0;
      if (n1 != n2) return n1.compareTo(n2);
    }
    return 0;
  }
}
