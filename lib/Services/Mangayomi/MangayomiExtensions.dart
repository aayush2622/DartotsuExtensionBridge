import 'dart:async';

import '../../Settings/KvStore.dart';
import '../../dartotsu_extension_bridge.dart';
import 'MangayomiExtensionManager.dart';
import 'MangayomiSourceMethods.dart';

class MangayomiExtensions extends Extension {
  @override
  String get id => 'mangayomi';

  @override
  String get name => 'Mangayomi';

  final _manager = MangayomiExtensionManager();
  @override
  SourceMethods createSourceMethods(Source source) =>
      MangayomiSourceMethods(source, _manager);

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
    switch (type) {
      case ItemType.anime:
        setVal('mangayomiAnimeRepos', repos);
        break;
      case ItemType.manga:
        setVal('mangayomiMangaRepos', repos);
        break;
      case ItemType.novel:
        setVal('mangayomiNovelRepos', repos);
        break;
    }

    final sources = await _manager.fetchAvailableExtensionsStream(type, repos);
    final installedIds = getInstalledRx(type).value.map((e) => e.id).toSet();

    final list = sources
        .map((e) {
          var map = e.toJson();
          map['extensionType'] = 0;
          map["id"] = e.sourceId;
          return Source.fromJson(map);
        })
        .where((s) => !installedIds.contains(s.id))
        .toList();

    getAvailableRx(type).value = list;
    checkForUpdates(type);
    return list;
  }

  @override
  Future<List<Source>> getInstalledAnimeExtensions({String? customPath}) =>
      _getInstalled(ItemType.anime);

  @override
  Future<List<Source>> getInstalledMangaExtensions({String? customPath}) =>
      _getInstalled(ItemType.manga);

  @override
  Future<List<Source>> getInstalledNovelExtensions() =>
      _getInstalled(ItemType.novel);

  Future<List<Source>> _getInstalled(ItemType type) async {
    final stream = _manager
        .getExtensionsStream(type)
        .map(
          (sources) => sources.map((s) {
            var map = s.toJson();
            map['extensionType'] = 0;
            map["id"] = s.sourceId;
            return Source.fromJson(map);
          }).toList(),
        )
        .asBroadcastStream();

    getInstalledRx(type).bindStream(stream);
    return stream.first;
  }

  @override
  Future<void> installSource(Source source, {String? customPath}) async {
    if (source.id?.isEmpty ?? true) {
      return Future.error('Source ID is required for installation.');
    }

    await _manager.installSource(source);

    final rx = getAvailableRx(source.itemType!);
    rx.value = rx.value.where((s) => s.id != source.id).toList();
  }

  @override
  Future<void> uninstallSource(Source source) async {
    if (source.id?.isEmpty ?? true) {
      return Future.error('Source ID is required for uninstallation.');
    }

    await _manager.uninstallSource(source);

    final availableList = _getAvailableList(source.itemType!);
    if (availableList.any((s) => s.sourceId == source.id)) {
      getAvailableRx(source.itemType!).update((list) => list?.add(source));
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

  @override
  Future<void> addRepo(String repoUrl, ItemType type) {
    // TODO: implement addRepo
    throw UnimplementedError();
  }

  @override
  Future<void> fetchAnimeExtensions() {
    // TODO: implement fetchAnimeExtensions
    throw UnimplementedError();
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() {
    // TODO: implement fetchInstalledAnimeExtensions
    throw UnimplementedError();
  }

  @override
  Future<void> fetchInstalledMangaExtensions() {
    // TODO: implement fetchInstalledMangaExtensions
    throw UnimplementedError();
  }

  @override
  Future<void> fetchInstalledNovelExtensions() {
    // TODO: implement fetchInstalledNovelExtensions
    throw UnimplementedError();
  }

  @override
  Future<void> fetchMangaExtensions() {
    // TODO: implement fetchMangaExtensions
    throw UnimplementedError();
  }

  @override
  Future<void> fetchNovelExtensions() {
    // TODO: implement fetchNovelExtensions
    throw UnimplementedError();
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) {
    // TODO: implement removeRepo
    throw UnimplementedError();
  }
}
