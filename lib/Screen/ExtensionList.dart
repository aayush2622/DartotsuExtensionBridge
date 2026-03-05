import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../ExtensionManager.dart';
import '../Models/Source.dart';

abstract class ExtensionConfig {
  ItemType get itemType;
  bool get isInstalled;
  String get searchQuery;
  String get selectedLanguage;
}

abstract class ExtensionList<T extends StatefulWidget> extends State<T> {
  final controller = ScrollController();
  final manager = Get.find<ExtensionManager>();
  ExtensionConfig get config => widget as ExtensionConfig;
  ItemType get itemType => config.itemType;
  bool get isInstalled => config.isInstalled;
  String get searchQuery => config.searchQuery;
  String get selectedLanguage => config.selectedLanguage;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    final ext = manager.current.value;
    switch (itemType) {
      case ItemType.anime:
        await ext.fetchAnimeExtensions();
        break;
      case ItemType.manga:
        await ext.fetchMangaExtensions();
        break;
      case ItemType.novel:
        await ext.fetchNovelExtensions();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ext = manager.current.value;
    final installedRx = ext.getInstalledRx(itemType);
    final availableRx = ext.getAvailableRx(itemType);
    return Obx(() {
      final fullList = isInstalled ? installedRx.value : availableRx.value;
      final search = searchQuery.toLowerCase();
      final filterLang = selectedLanguage == 'All' || selectedLanguage == 'all'
          ? null
          : selectedLanguage;
      final Map<String, List<Source>> grouped = {};
      for (final source in fullList) {
        final lang = source.lang ?? 'Unknown';
        if (filterLang != null && lang != filterLang) continue;
        if (search.isNotEmpty &&
            !(source.name?.toLowerCase().contains(search) ?? false)) {
          continue;
        }
        grouped.putIfAbsent(lang, () => []).add(source);
      }
      final sortedEntries = grouped.entries.toList()
        ..sort((a, b) {
          if (a.key == 'all') return -1;
          if (b.key == 'all') return 1;
          if (a.key == 'en') return -1;
          if (b.key == 'en') return 1;
          return a.key.compareTo(b.key);
        });
      final flattenedList = <({bool isHeader, String lang, Source? source})>[];
      for (final entry in sortedEntries) {
        flattenedList.add((isHeader: true, lang: entry.key, source: null));
        for (final source in entry.value) {
          flattenedList.add((isHeader: false, lang: entry.key, source: source));
        }
      }
      return RefreshIndicator(
        onRefresh: _refreshData,
        child: CustomScrollView(
          controller: controller,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  childCount: flattenedList.length,
                  (context, index) {
                    final item = flattenedList[index];
                    return extensionItem(
                      item.isHeader,
                      item.lang,
                      item.source,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget extensionItem(bool isHeader, String lang, Source? source);
}
