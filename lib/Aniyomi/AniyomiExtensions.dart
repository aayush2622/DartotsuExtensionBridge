import 'package:dartotsu_extension_bridge/Extensions/Extensions.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';

import '../Settings/Settings.dart';
import '../extension_bridge.dart';

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
  Future<void> installSource(Source source) {
    // TODO: implement installSource
    throw UnimplementedError();
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
