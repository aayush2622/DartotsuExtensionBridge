import 'dart:io';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:http/http.dart' as http;
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
    if (source.id == null) {
      return Future.error('Source ID is required for installation.');
    }

    try {
      final packageName = source.id!.split('/').last;

      final response = await http.get(Uri.parse(source.id!));

      if (response.statusCode != 200) {
        throw Exception('Failed to download APK: HTTP ${response.statusCode}');
      }

      final tempDir = await getTemporaryDirectory();
      final apkFileName = '$packageName.apk';
      final apkFile = File(path.join(tempDir.path, apkFileName));

      await apkFile.writeAsBytes(response.bodyBytes);

      final result = await platform.invokeMethod('installExtension', {
        'apkPath': apkFile.path,
      });

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      if (!result) {
        throw Exception('Installation failed');
      }
      debugPrint('Installed package: $packageName');
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
    try {
      final packageName = source.id!.split('/').last;

      final result = await platform.invokeMethod('uninstallExtension', {
        'packageName': packageName,
      });

      if (!result) {
        throw Exception('Uninstallation failed or package not found');
      }

      debugPrint('Uninstalled package: $packageName');
    } catch (e) {
      if (kDebugMode) {
        print('Error uninstalling source: $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> updateSource(Source source) {
    throw UnimplementedError();
  }
}
