import 'dart:convert';

import 'package:dartotsu_extension_bridge/Mangayomi/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:isar/isar.dart';

import '../extension_bridge.dart';
import 'http/m_client.dart';
import 'lib.dart';

class MangayomiExtensionManager extends GetxController {
  final installedAnimeExtensions = Rx<List<MSource>>([]);
  final availableAnimeExtensions = Rx<List<MSource>>([]);
  final installedMangaExtensions = Rx<List<MSource>>([]);
  final availableMangaExtensions = Rx<List<MSource>>([]);
  final installedNovelExtensions = Rx<List<MSource>>([]);
  final availableNovelExtensions = Rx<List<MSource>>([]);
  final http = MClient.init(reqcopyWith: {'useDartHttpClient': true});

  @override
  void onInit() {
    super.onInit();
    installedAnimeExtensions.bindStream(getExtensionsStream(ItemType.anime));
    installedMangaExtensions.bindStream(getExtensionsStream(ItemType.manga));
    installedNovelExtensions.bindStream(getExtensionsStream(ItemType.novel));
  }

  Stream<List<MSource>> getExtensionsStream(ItemType itemType) async* {
    yield* isar.mSources
        .filter()
        .idIsNotNull()
        .and()
        .itemTypeEqualTo(itemType)
        .watch(fireImmediately: true);
  }

  Future<List<MSource>> fetchAvailableExtensionsStream(
    ItemType itemType,
    List<String>? repos,
  ) async {
    var sources = <MSource>[];

    if (repos == null || repos.isEmpty) return sources;

    for (final repo in repos) {
      if (repo.trim().isEmpty) continue;
      final req = await http.get(Uri.parse(repo.trim()));
      if (req.statusCode != 200) {
        debugPrint("Failed to fetch sources from $repo: ${req.statusCode}");
        continue;
      }
      final sourceList = (jsonDecode(req.body) as List)
          .map((e) => MSource.fromJson(e)..repo = repo)
          .where((source) => source.itemType == itemType)
          .toList();

      sources.addAll(sourceList);
    }
    switch (itemType) {
      case ItemType.anime:
        availableAnimeExtensions.value = sources;
        break;
      case ItemType.manga:
        availableMangaExtensions.value = sources;
        break;
      case ItemType.novel:
        availableNovelExtensions.value = sources;
        break;
    }

    return sources;
  }

  Future<void> installSource(Source source) async {
    try {
      var mSource = await getAvailable(source.itemType!, int.parse(source.id!));
      final req = await http.get(Uri.parse(mSource.sourceCodeUrl!));
      final headers = getExtensionService(
        mSource..sourceCode = req.body,
      ).getHeaders();

      var s = mSource
        ..sourceCode = req.body
        ..headers = jsonEncode(headers);

      await isar.writeTxnSync(() async => isar.mSources.putSync(s));
    } catch (e) {
      debugPrint("Error installing source: $e");
      return Future.error(e);
    }
  }

  Future<void> uninstallSource(Source source) async {
    try {
      var mSource = await getInstalled(source.itemType!, int.parse(source.id!));
      await isar.writeTxnSync(
        () async => isar.mSources.deleteSync(mSource.id!),
      );
    } catch (e) {
      debugPrint("Error uninstalling source: $e");
      return Future.error(e);
    }
  }

  Future<void> updateSource(Source source) async {
    try {
      var mSource = await getAvailable(source.itemType!, int.parse(source.id!));
      final req = await http.get(Uri.parse(mSource.sourceCodeUrl!));
      final headers = getExtensionService(
        mSource..sourceCode = req.body,
      ).getHeaders();

      var s = mSource
        ..sourceCode = req.body
        ..version = source.version
        ..headers = jsonEncode(headers);

      await isar.writeTxnSync(() async => isar.mSources.putSync(s));
    } catch (e) {
      debugPrint("Error updating source: $e");
      return Future.error(e);
    }
  }

  Future<MSource> getAvailable(ItemType itemType, int id) async {
    switch (itemType) {
      case ItemType.anime:
        return availableAnimeExtensions.value.firstWhere(
          (source) => source.id == id,
          orElse: () => throw Exception('Source not found'),
        );
      case ItemType.manga:
        return availableMangaExtensions.value.firstWhere(
          (source) => source.id == id,
          orElse: () => throw Exception('Source not found'),
        );
      case ItemType.novel:
        return availableNovelExtensions.value.firstWhere(
          (source) => source.id == id,
          orElse: () => throw Exception('Source not found'),
        );
    }
  }

  Future<MSource> getInstalled(ItemType itemType, int id) async {
    switch (itemType) {
      case ItemType.anime:
        return installedAnimeExtensions.value.firstWhere(
          (source) => source.id == id,
          orElse: () => throw Exception('Source not found'),
        );
      case ItemType.manga:
        return installedMangaExtensions.value.firstWhere(
          (source) => source.id == id,
          orElse: () => throw Exception('Source not found'),
        );
      case ItemType.novel:
        return installedNovelExtensions.value.firstWhere(
          (source) => source.id == id,
          orElse: () => throw Exception('Source not found'),
        );
    }
  }
}
