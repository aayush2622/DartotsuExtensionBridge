import 'dart:io';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:device_apps/device_apps.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:http/http.dart' as http;
import 'package:install_plugin/install_plugin.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../Settings/Settings.dart';

class AniyomiExtensions extends Extension {
  AniyomiExtensions() {
    initialize();
  }

  static const platform = MethodChannel('aniyomiExtensionBridge');

  @override
  bool get supportsNovel => false;

  @override
  Future<List<Source>> getInstalledAnimeExtensions() {
    return _loadExtensions(
      'getInstalledAnimeExtensions',
      installedAnimeExtensions,
    );
  }

  @override
  Future<List<Source>> fetchAvailableAnimeExtensions(List<String>? repos) {
    var settings = isar.bridgeSettings.getSync(26)!;
    isar.writeTxnSync(
      () => isar.bridgeSettings.putSync(
        settings..aniyomiAnimeExtensions = repos ?? [],
      ),
    );
    return _loadExtensions(
      'fetchAnimeExtensions',
      availableAnimeExtensions,
      repos: repos,
    );
  }

  @override
  Future<List<Source>> getInstalledMangaExtensions() {
    return _loadExtensions(
      'getInstalledMangaExtensions',
      installedMangaExtensions,
    );
  }

  @override
  Future<List<Source>> fetchAvailableMangaExtensions(List<String>? repos) {
    var settings = isar.bridgeSettings.getSync(26)!;
    isar.writeTxnSync(
      () => isar.bridgeSettings.putSync(
        settings..aniyomiMangaExtensions = repos ?? [],
      ),
    );
    return _loadExtensions(
      'fetchMangaExtensions',
      availableMangaExtensions,
      repos: repos,
    );
  }

  Future<List<Source>> _loadExtensions(
    String method,
    Rx<List<Source>> target, {
    List<String>? repos,
  }) async {
    try {
      final List<dynamic> result = await platform.invokeMethod(method, repos);
      final parsed = await compute(_parseSources, result);
      target.value = parsed;
      return parsed;
    } catch (e) {
      target.value = [];
      return [];
    }
  }

  static List<Source> _parseSources(List<dynamic> data) {
    return data
        .map(
          (e) => Source.fromJson(
            Map<String, dynamic>.from(e),
            ExtensionType.aniyomi,
          ),
        )
        .toList();
  }

  @override
  Future<void> initialize() async {
    if (isInitialized.value) return;
    isInitialized.value = true;
    var settings = isar.bridgeSettings.getSync(26) ?? BridgeSettings();
    getInstalledAnimeExtensions();
    getInstalledMangaExtensions();
    getInstalledNovelExtensions();
    fetchAvailableAnimeExtensions(settings.aniyomiAnimeExtensions);
    fetchAvailableMangaExtensions(settings.aniyomiMangaExtensions);
  }

  @override
  Future<void> installSource(Source source) async {
    if (source.apkUrl == null) {
      return Future.error('Source APK URL is required for installation.');
    }

    try {
      final packageName = source.apkUrl!.split('/').last.replaceAll('.apk', '');

      final response = await http.get(Uri.parse(source.apkUrl!));

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
      switch (source.itemType) {
        case ItemType.anime:
          availableAnimeExtensions.value = availableAnimeExtensions.value
              .where((e) => e.name != source.name)
              .toList();
          break;
        case ItemType.manga:
          availableMangaExtensions.value = availableMangaExtensions.value
              .where((e) => e.name != source.name)
              .toList();
          break;
        case null:
          throw Exception("Item type is null");
        case ItemType.novel:
          break;
      }
      switch (source.itemType) {
        case ItemType.anime:
          installedAnimeExtensions.value.add(source);
          break;
        case ItemType.manga:
          installedMangaExtensions.value.add(source);
          break;
        case null:
          throw Exception("Item type is null");
        case ItemType.novel:
          break;
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
    if (source.id == null) {
      return Future.error('Source ID is required for uninstallation.');
    }

    final packageName = source.id!;

    try {
      final app = await DeviceApps.getApp(packageName);

      if (app == null) {
        throw Exception('Package not found: $packageName');
      }

      final uninstalled = await DeviceApps.uninstallApp(packageName);

      if (!uninstalled) {
        throw Exception('Failed to uninstall');
      } else {
        switch (source.itemType) {
          case ItemType.anime:
            installedAnimeExtensions.value = installedAnimeExtensions.value
                .where((e) => e.name != source.name)
                .toList();
            break;
          case ItemType.manga:
            installedMangaExtensions.value = installedMangaExtensions.value
                .where((e) => e.name != source.name)
                .toList();
            break;
          case null:
            throw Exception("Item type is null");
          case ItemType.novel:
            break;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error opening uninstall settings: $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> updateSource(Source source) {
    throw UnimplementedError();
  }
}
