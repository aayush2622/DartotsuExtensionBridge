import 'dart:async';
import 'dart:io';

import 'package:device_apps/device_apps.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:http/http.dart' as http;
import 'package:install_plugin/install_plugin.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../Logger.dart';
import '../../Settings/KvStore.dart';
import '../../dartotsu_extension_bridge.dart';
import 'AniyomiSourceMethods.dart';
import 'Models/Source.dart';

class AniyomiExtensions extends Extension {
  AniyomiExtensions() {
    initialize();
  }
  @override
  String get id => 'aniyomi';

  @override
  String get name => 'Aniyomi';

  @override
  SourceMethods createSourceMethods(Source source) =>
      AniyomiSourceMethods(source);

  static const platform = MethodChannel('aniyomiExtensionBridge');
  final Rx<List<Source>> availableAnimeExtensionsUnmodified = Rx([]);
  final Rx<List<Source>> availableMangaExtensionsUnmodified = Rx([]);
  final Rx<List<Source>> availableNovelExtensionsUnmodified = Rx([]);

  @override
  bool get supportsNovel => false;

  @override
  Future<List<Source>> fetchAvailableAnimeExtensions(List<String>? repos) =>
      _fetchAvailable('fetchAnimeExtensions', ItemType.anime, repos);

  @override
  Future<List<Source>> fetchAvailableMangaExtensions(List<String>? repos) =>
      _fetchAvailable('fetchMangaExtensions', ItemType.manga, repos);

  Future<List<Source>> _fetchAvailable(
    String method,
    ItemType type,
    List<String>? repos,
  ) async {
    switch (type) {
      case ItemType.anime:
        setVal('aniyomiAnimeRepos', repos);
        break;
      case ItemType.manga:
        setVal('aniyomiMangaRepos', repos);
        break;
      case ItemType.novel:
        break;
    }

    final sources = await _loadExtensions(method, repos: repos);
    final installedIds = getInstalledRx(type).value.map((e) => e.id).toSet();

    final unmodifiedList = sources.map((e) {
      final src = e as ASource;
      src.extensionType = 1;
      return src;
    }).toList();
    final list =
        unmodifiedList.where((s) => !installedIds.contains(s.id)).toList();
    getAvailableRx(type).value = list;
    getAvailableUnmodified(type).value = unmodifiedList;
    checkForUpdates(type);
    return list;
  }

  @override
  Future<List<Source>> getInstalledAnimeExtensions() {
    return _getInstalled(
      'getInstalledAnimeExtensions',
      ItemType.anime,
    );
  }

  @override
  Future<List<Source>> getInstalledMangaExtensions() {
    return _getInstalled(
      'getInstalledMangaExtensions',
      ItemType.manga,
    );
  }

  Future<List<Source>> _getInstalled(
    String method,
    ItemType type,
  ) async {
    final sources = await _loadExtensions(method);
    getInstalledRx(type).value = sources;
    checkForUpdates(type);
    return sources;
  }

  Future<List<Source>> _loadExtensions(
    String method, {
    List<String>? repos,
  }) async {
    try {
      final List<dynamic> result = await platform.invokeMethod(method, repos);
      final parsed = await compute(_parseSources, result);
      return parsed;
    } catch (e) {
      return [];
    }
  }

  static List<Source> _parseSources(List<dynamic> data) {
    return data.map((e) {
      final map = Map<String, dynamic>.from(e);

      map['apkUrl'] = getAnimeApkUrl(
        map['iconUrl'] ?? '',
        map['apkName'] ?? '',
      );

      return ASource.fromJson(map);
    }).toList();
  }

  @override
  Future<void> installSource(Source source, {String? customPath}) async {
    var aSource = source as ASource;
    if (aSource.apkUrl == null) {
      return Future.error('Source APK URL is required for installation.');
    }

    try {
      final packageName =
          aSource.apkUrl!.split('/').last.replaceAll('.apk', '');

      final response = await http.get(Uri.parse(aSource.apkUrl!));

      if (response.statusCode != 200) {
        throw Exception('Failed to download APK: HTTP ${response.statusCode}');
      }

      final tempDir = await getTemporaryDirectory();
      final apkFileName = '$packageName.apk';
      final apkFile = File(path.join(tempDir.path, apkFileName));

      await apkFile.writeAsBytes(response.bodyBytes);

      final result = await InstallPlugin.installApk(
        apkFile.path,
        appId: packageName,
      );

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      if (result['isSuccess'] != true) {
        throw Exception(
          'Installation failed: ${result['errorMessage'] ?? 'Unknown error'}',
        );
      }
      final rx = getAvailableRx(aSource.itemType!);
      rx.value = rx.value.where((s) => s.id != aSource.id).toList();
      switch (aSource.itemType) {
        case ItemType.anime:
          getInstalledAnimeExtensions(); // because it also update extension on kotlin side
          break;
        case ItemType.manga:
          getInstalledMangaExtensions();
          break;
        case ItemType.novel:
          break;
        default:
          throw Exception('Unsupported item type: ${source.itemType}');
      }
      Logger.log('Successfully installed package: $packageName');
    } catch (e) {
      Logger.log('Error installing source: $e');
      rethrow;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final packageName = source.id;
    if (packageName == null || packageName.isEmpty) {
      throw Exception('Source ID is required for uninstallation.');
    }

    try {
      final isInstalled = await DeviceApps.isAppInstalled(packageName);
      if (!isInstalled) {
        _removeFromInstalledList(source);
        return;
      }

      final success = await DeviceApps.uninstallApp(packageName);
      if (!success) {
        throw Exception('Failed to initiate uninstallation for: $packageName');
      }

      final timeout = const Duration(seconds: 10);
      final start = DateTime.now();

      while (DateTime.now().difference(start) < timeout) {
        final stillInstalled = await DeviceApps.isAppInstalled(packageName);
        if (!stillInstalled) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final finalCheck = await DeviceApps.isAppInstalled(packageName);
      if (finalCheck) {
        throw Exception('Uninstallation timed out or was cancelled by user.');
      }

      _removeFromInstalledList(source);

      final itemType = source.itemType;
      if (itemType != null) {
        final availableList = getAvailableUnmodified(itemType).value;
        if (availableList.any((s) => s.id == packageName)) {
          getAvailableRx(itemType).update((list) => list?..add(source));
        }
      }

      Logger.log('Successfully uninstalled package: $packageName');
    } catch (e) {
      Logger.log('Error uninstalling $packageName: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    await installSource(source);
  }

  void _removeFromInstalledList(Source source) {
    /* switch (source.itemType) {
      case ItemType.anime:
        installedAnimeExtensions.value = installedAnimeExtensions.value
            .where((e) => e.id != source.id)
            .toList();
        break;
      case ItemType.manga:
        installedMangaExtensions.value = installedMangaExtensions.value
            .where((e) => e.id != source.id)
            .toList();
        break;
      case ItemType.novel:
        installedNovelExtensions.value = installedNovelExtensions.value
            .where((e) => e.id != source.id)
            .toList();
        break;
      case null:
        break;
    }*/
  }

  Rx<List<Source>> getAvailableUnmodified(ItemType type) {
    switch (type) {
      case ItemType.anime:
        return availableAnimeExtensionsUnmodified;
      case ItemType.manga:
        return availableMangaExtensionsUnmodified;
      case ItemType.novel:
        return availableNovelExtensionsUnmodified;
    }
  }

  Future<void> checkForUpdates(ItemType type) async {
    final availableMap = {
      for (var s in getAvailableUnmodified(type).value) s.id: s,
    };

    final updated = getInstalledRx(type).value.map((i) {
      var installed = i as ASource;
      final avail = availableMap[installed.id ?? ''] as ASource?;
      if (avail != null &&
          installed.version != null &&
          avail.version != null &&
          compareVersions(installed.version!, avail.version!) < 0) {
        return installed
          ..hasUpdate = true
          ..apkUrl = avail.apkUrl
          ..versionLast = avail.version;
      }
      return installed;
    }).toList();

    getInstalledRx(type).value = updated;
  }

  static String getAnimeApkUrl(String iconUrl, String apkName) {
    if (iconUrl.isEmpty || apkName.isEmpty) return "";

    final baseUrl = iconUrl.replaceFirst('icon/', 'apk/');
    final lastSlash = baseUrl.lastIndexOf('/');
    if (lastSlash == -1) return "";

    final cleanedUrl = baseUrl.substring(0, lastSlash);
    return '$cleanedUrl/$apkName';
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
