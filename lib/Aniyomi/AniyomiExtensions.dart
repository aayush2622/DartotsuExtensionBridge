import 'dart:io';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart' as aniyomi;
import 'package:objectbox/objectbox.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';

class AniyomiExtensions extends Extension {
  AniyomiExtensions() {
    initialize();
  }

  static const platform = MethodChannel('aniyomiExtensionBridge');
  final Rx<List<Source>> availableAnimeExtensionsUnmodified = Rx([]);
  final Rx<List<Source>> availableMangaExtensionsUnmodified = Rx([]);
  final Rx<List<Source>> availableNovelExtensionsUnmodified = Rx([]);

  // Reusable Dio client
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  // ObjectBox store and boxes
  static late final Store objectboxStore;
  static late final Box<BridgeSettings> bridgeSettingsBox;

  static Future<void> setupObjectBox(Store store) async {
    objectboxStore = store;
    bridgeSettingsBox = store.box<BridgeSettings>();
  }

  BridgeSettings getBridgeSettings(int id) {
    return bridgeSettingsBox.get(id)!;
  }

  void putBridgeSettings(BridgeSettings settings) {
    bridgeSettingsBox.put(settings);
  }

  @override
  bool get supportsNovel => false;

  @override
  Future<void> initialize() async {
    if (isInitialized.value) return;
    isInitialized.value = true;

    // Optional: log current app info using package_info_plus
    try {
      final info = await PackageInfo.fromPlatform();
      debugPrint(
        'AniyomiExtensions host: ${info.packageName} v${info.version}+${info.buildNumber}',
      );
    } catch (_) {
      // Ignore failures to obtain package info
    }

    var settings = getBridgeSettings(26);
    getInstalledAnimeExtensions();
    getInstalledMangaExtensions();
    getInstalledNovelExtensions();
    fetchAvailableAnimeExtensions(settings.aniyomiAnimeExtensions);
    fetchAvailableMangaExtensions(settings.aniyomiMangaExtensions);
  }

  @override
  Future<List<Source>> fetchAvailableAnimeExtensions(List<String>? repos) =>
      _fetchAvailable('fetchAnimeExtensions', aniyomi.ItemType.anime, repos);

  @override
  Future<List<Source>> fetchAvailableMangaExtensions(List<String>? repos) =>
      _fetchAvailable('fetchMangaExtensions', aniyomi.ItemType.manga, repos);

  Future<List<Source>> _fetchAvailable(
    String method,
    aniyomi.ItemType type,
    List<String>? repos,
  ) async {
    final settings = getBridgeSettings(26);

    switch (type) {
      case aniyomi.ItemType.anime:
        settings.aniyomiAnimeExtensions = repos ?? [];
        break;
      case aniyomi.ItemType.manga:
        settings.aniyomiMangaExtensions = repos ?? [];
        break;
      case aniyomi.ItemType.novel:
        break;
    }
    putBridgeSettings(settings);

    final sources = await _loadExtensions(method, repos: repos);
    final installedIds = getInstalledRx(type).value.map((e) => e.id).toSet();

    final unmodifiedList = sources.map((e) {
      var map = e.toJson();
      map['extensionType'] = 1;
      return Source.fromJson(map);
    }).toList();

    final list = unmodifiedList
        .where((s) => !installedIds.contains(s.id))
        .toList();

    getAvailableRx(type).value = list;
    getAvailableUnmodified(type).value = unmodifiedList;
    checkForUpdates(type);
    return list;
  }

  @override
  Future<List<Source>> getInstalledAnimeExtensions() {
    return _getInstalled('getInstalledAnimeExtensions', aniyomi.ItemType.anime);
  }

  @override
  Future<List<Source>> getInstalledMangaExtensions() {
    return _getInstalled('getInstalledMangaExtensions', aniyomi.ItemType.manga);
  }

  // Added for completeness since initialize() calls this.
  @override
  Future<List<Source>> getInstalledNovelExtensions() {
    return _getInstalled('getInstalledNovelExtensions', aniyomi.ItemType.novel);
  }

  Future<List<Source>> _getInstalled(
    String method,
    aniyomi.ItemType type,
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
      map['extensionType'] = 1;
      return Source.fromJson(map);
    }).toList();
  }

  @override
  Future<void> installSource(Source source) async {
    if (source.apkUrl == null) {
      return Future.error('Source APK URL is required for installation.');
    }

    try {
      final packageName = source.apkUrl!.split('/').last.replaceAll('.apk', '');

      final tempDir = await getTemporaryDirectory();
      final apkFileName = '$packageName.apk';
      final apkFile = File(path.join(tempDir.path, apkFileName));

      // Download APK via Dio (writes directly to file)
      await _dio.download(
        source.apkUrl!,
        apkFile.path,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 2),
        ),
        deleteOnError: true,
      );

      // Sanity check
      if (!(await apkFile.exists()) || (await apkFile.length()) == 0) {
        throw Exception('Failed to download APK: Empty file');
      }

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

      final rx = getAvailableRx(source.itemType!);
      rx.value = rx.value.where((s) => s.id != source.id).toList();

      switch (source.itemType) {
        case aniyomi.ItemType.anime:
          getInstalledAnimeExtensions();
          break;
        case aniyomi.ItemType.manga:
          getInstalledMangaExtensions();
          break;
        case aniyomi.ItemType.novel:
          break;
        default:
          throw Exception('Unsupported item type: ${source.itemType}');
      }
      debugPrint('Successfully installed package: $packageName');
    } catch (e) {
      if (kDebugMode) {
        print('Error installing source: $e');
      }
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
      // Request system uninstall via platform channel (e.g., Android ACTION_DELETE intent).
      final bool started =
          (await platform.invokeMethod('uninstallApp', { 'package': packageName })) == true;
      if (!started) {
        throw Exception('Failed to initiate uninstallation for: $packageName');
      }

      // Optimistic local update
      _removeFromInstalledList(source);

      final itemType = source.itemType;
      if (itemType != null) {
        final availableList = getAvailableUnmodified(itemType).value;
        if (availableList.any((s) => s.id == packageName)) {
          getAvailableRx(itemType).update((list) => list?..add(source));
        }
      }

      debugPrint('Uninstall requested for package: $packageName');
    } catch (e) {
      debugPrint('Error uninstalling $packageName: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    if (source.apkUrl == null) {
      return Future.error('Source APK URL is required for installation.');
    }

    try {
      final packageName = source.apkUrl!.split('/').last.replaceAll('.apk', '');

      final tempDir = await getTemporaryDirectory();
      final apkFileName = '$packageName.apk';
      final apkFile = File(path.join(tempDir.path, apkFileName));

      // Download APK via Dio (writes directly to file)
      await _dio.download(
        source.apkUrl!,
        apkFile.path,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 2),
        ),
        deleteOnError: true,
      );

      // Sanity check
      if (!(await apkFile.exists()) || (await apkFile.length()) == 0) {
        throw Exception('Failed to download APK: Empty file');
      }

      final result = await InstallPlugin.installApk(
        apkFile.path,
        appId: packageName,
      );

      if (result['isSuccess'] != true) {
        debugPrint(
          'Installation failed: ${result['errorMessage'] ?? 'Unknown error'}',
        );
      }
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      switch (source.itemType) {
        case aniyomi.ItemType.anime:
          getInstalledAnimeExtensions();
          break;
        case aniyomi.ItemType.manga:
          getInstalledMangaExtensions();
          break;
        case aniyomi.ItemType.novel:
          break;
        default:
          throw Exception('Unsupported item type: ${source.itemType}');
      }
      debugPrint('Successfully updated package: $packageName');
    } catch (e) {
      if (kDebugMode) {
        print('Error installing source: $e');
      }
      rethrow;
    }
  }

  void _removeFromInstalledList(Source source) {
    switch (source.itemType) {
      case aniyomi.ItemType.anime:
        installedAnimeExtensions.value = installedAnimeExtensions.value
            .where((e) => e.name != source.name)
            .toList();
        break;
      case aniyomi.ItemType.manga:
        installedMangaExtensions.value = installedMangaExtensions.value
            .where((e) => e.name != source.name)
            .toList();
        break;
      case aniyomi.ItemType.novel:
        installedNovelExtensions.value = installedNovelExtensions.value
            .where((e) => e.name != source.name)
            .toList();
        break;
      case null:
        break;
    }
  }

  Rx<List<Source>> getAvailableUnmodified(aniyomi.ItemType type) {
    switch (type) {
      case aniyomi.ItemType.anime:
        return availableAnimeExtensionsUnmodified;
      case aniyomi.ItemType.manga:
        return availableMangaExtensionsUnmodified;
      case aniyomi.ItemType.novel:
        return availableNovelExtensionsUnmodified;
    }
  }

  Future<void> checkForUpdates(aniyomi.ItemType type) async {
    final availableMap = {
      for (var s in getAvailableUnmodified(type).value) s.id: s,
    };

    final updated = getInstalledRx(type).value.map((installed) {
      final avail = availableMap[installed.id ?? ''];
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
}
