import 'package:dartotsu_extension_bridge/Extensions/Extensions.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';

class AniyomiExtensions extends Extension {
  static const platform = MethodChannel('aniyomiExtensionBridge');

  @override
  Future<List<Source>> getInstalledAnimeExtensions() {
    return _loadExtensions(
      'getInstalledAnimeExtensions',
      installedAnimeExtensions,
    );
  }

  @override
  Future<List<Source>> fetchAvailableAnimeExtensions(List<String>? repos) {
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
        .map((e) => Source.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Extension> init() async {
    installedAnimeExtensions.value = await getInstalledAnimeExtensions();
    installedMangaExtensions.value = await getInstalledMangaExtensions();
    availableAnimeExtensions.value = await fetchAvailableAnimeExtensions([
      'https://raw.githubusercontent.com/yuzono/anime-repo/repo/index.min.json',
    ]);
    availableMangaExtensions.value = await fetchAvailableMangaExtensions([
      'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
    ]);
    return this;
  }
}
