import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:get/get.dart';
import 'package:objectbox/objectbox.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart' as core;
import 'package:dartotsu_extension_bridge/Mangayomi/Models/Source.dart'
    as manga;
import 'MangayomiExtensionManager.dart';

class MangayomiExtensions extends Extension {
  MangayomiExtensions() {
    initialize();
  }

  manga.ItemType toMangaItemType(core.ItemType type) {
    switch (type) {
      case core.ItemType.anime:
        return manga.ItemType.anime;
      case core.ItemType.manga:
        return manga.ItemType.manga;
      case core.ItemType.novel:
        return manga.ItemType.novel;
    }
  }

  final _manager = Get.put(MangayomiExtensionManager());

  // Use the global ObjectBox store initialized in extension_bridge.dart
  late final Box<BridgeSettings> _settingsBox = objectboxStore.box<BridgeSettings>();

  BridgeSettings _getSettings() {
    final settings = _settingsBox.get(26);
    if (settings == null) throw Exception('BridgeSettings not found');
    return settings;
  }

  void _putSettings(BridgeSettings settings) {
    _settingsBox.put(settings);
  }

  @override
  Future<void> initialize() async {
    if (isInitialized.value) return;
    isInitialized.value = true;

    final settings = _getSettings();

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
  Future<List<core.Source>> fetchAvailableAnimeExtensions(
    List<String>? repos,
  ) => _fetchAvailable(core.ItemType.anime, repos);

  @override
  Future<List<core.Source>> fetchAvailableMangaExtensions(
    List<String>? repos,
  ) => _fetchAvailable(core.ItemType.manga, repos);

  @override
  Future<List<core.Source>> fetchAvailableNovelExtensions(
    List<String>? repos,
  ) => _fetchAvailable(core.ItemType.novel, repos);

  Future<List<core.Source>> _fetchAvailable(
    core.ItemType type,
    List<String>? repos,
  ) async {
    final settings = _getSettings();

    switch (type) {
      case core.ItemType.anime:
        settings.mangayomiAnimeExtensions = repos ?? [];
        break;
      case core.ItemType.manga:
        settings.mangayomiMangaExtensions = repos ?? [];
        break;
      case core.ItemType.novel:
        settings.mangayomiNovelExtensions = repos ?? [];
        break;
    }
    _putSettings(settings);

    final sources = await _manager.fetchAvailableExtensionsStream(type, repos);
    final installedIds = getInstalledRx(type).value.map((e) => e.id).toSet();

    final list = sources
        .map((e) {
          var map = e.toJson();
          map['extensionType'] = 0;
          return core.Source.fromJson(map);
        })
        .where((s) => !installedIds.contains(s.id))
        .toList();

    getAvailableRx(type).value = list;
    checkForUpdates(type);
    return list;
  }

  @override
  Future<List<core.Source>> getInstalledAnimeExtensions() =>
      _getInstalled(core.ItemType.anime);

  @override
  Future<List<core.Source>> getInstalledMangaExtensions() =>
      _getInstalled(core.ItemType.manga);

  @override
  Future<List<core.Source>> getInstalledNovelExtensions() =>
      _getInstalled(core.ItemType.novel);

  Future<List<core.Source>> _getInstalled(core.ItemType type) async {
    final stream = _manager
        .getExtensionsStream(type)
        .map(
          (sources) => sources.map((s) {
            var map = s.toJson();
            map['extensionType'] = 0;
            return core.Source.fromJson(map);
          }).toList(),
        )
        .asBroadcastStream();

    getInstalledRx(type).bindStream(stream);
    return stream.first;
  }

  @override
  Future<void> installSource(core.Source source) async {
    if (source.id?.isEmpty ?? true) {
      return Future.error('Source ID is required for installation.');
    }

    await _manager.installSource(source);

    final rx = getAvailableRx(source.itemType!);
    rx.value = rx.value.where((s) => s.id != source.id).toList();
  }

  @override
  Future<void> uninstallSource(core.Source source) async {
    if (source.id?.isEmpty ?? true) {
      return Future.error('Source ID is required for uninstallation.');
    }

    await _manager.uninstallSource(source);

    final availableList = _getAvailableList(source.itemType!);
    final idInt = int.tryParse(source.id ?? '');
    if (idInt != null && availableList.any((s) => s.id == idInt)) {
      getAvailableRx(source.itemType!).update((list) => list?.add(source));
    }
  }

  @override
  Future<void> updateSource(core.Source source) async {
    if (source.id?.isEmpty ?? true) {
      return Future.error('Source ID is required for update.');
    }
    await _manager.updateSource(source);
  }

  Future<void> checkForUpdates(core.ItemType type) async {
    final availableMap = {for (var s in _getAvailableList(type)) s.id: s};

    final updated = getInstalledRx(type).value.map((installed) {
      final avail = availableMap[int.tryParse(installed.id ?? '')];
      if (avail != null &&
          installed.version != null &&
          avail.version != null &&
          compareVersions(installed.version!, avail.version!) < 0) {
        return installed
          ..hasUpdate = true
          ..versionLast = avail.version;
      }
      return installed;
    }).toList();

    getInstalledRx(type).value = updated;
  }

  List<manga.MSource> _getAvailableList(core.ItemType type) {
    switch (type) {
      case core.ItemType.anime:
        return _manager.availableAnimeExtensions.value;
      case core.ItemType.manga:
        return _manager.availableMangaExtensions.value;
      case core.ItemType.novel:
        return _manager.availableNovelExtensions.value;
    }
  }
}
