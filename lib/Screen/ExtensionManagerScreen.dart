import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../ExtensionManager.dart';
import '../Extensions/Extensions.dart';
import '../Models/Source.dart';

abstract class ExtensionManagerScreen<T extends StatefulWidget> extends State<T>
    with TickerProviderStateMixin {
  late TabController _tabBarController;

  final managerController = Get.find<ExtensionManager>();

  final _selectedLanguage = 'All'.obs;
  final _textEditingController = TextEditingController();

  Extension get manager => managerController.current.value;

  @override
  void initState() {
    super.initState();

    int totalTabs = 0;
    if (manager.supportsAnime) totalTabs += 2;
    if (manager.supportsManga) totalTabs += 2;
    if (manager.supportsNovel) totalTabs += 2;

    _tabBarController = TabController(length: totalTabs, vsync: this);
  }

  @override
  void dispose() {
    _tabBarController.dispose();
    _textEditingController.dispose();
    _selectedLanguage.close();
    super.dispose();
  }

  Text get title;

  ExtensionScreenBuilder get extensionScreenBuilder;

  List<Widget> extensionActions(
    BuildContext context,
    TabController tabController,
    String currentLanguage,
    void Function(String currentLanguage) onLanguageChanged,
  );

  Widget tabWidget(BuildContext context, String label, int count);

  Widget searchBar(
    BuildContext context,
    TextEditingController controller,
    void Function() onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        physics: const BouncingScrollPhysics(),
        scrollbars: false,
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          title: title,
          iconTheme: IconThemeData(color: theme.primary),
          actions: [
            ...extensionActions(
              context,
              _tabBarController,
              _selectedLanguage.value,
              (lang) => _selectedLanguage.value = lang,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Obx(
              () => TabBar(
                controller: _tabBarController,
                isScrollable: true,
                indicatorSize: TabBarIndicatorSize.label,
                dragStartBehavior: DragStartBehavior.start,
                tabs: _buildTabs(context),
              ),
            ),
            const SizedBox(height: 8),
            searchBar(
              context,
              _textEditingController,
              () => setState(() {}),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Expanded(
                child: TabBarView(
                  controller: _tabBarController,
                  children: _buildTabViews(theme, extensionScreenBuilder),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTabs(BuildContext context) {
    final ext = manager;

    List<Widget> tabs = [];

    void addTabs(ItemType type, String label) {
      final installed = ext.getInstalledRx(type).value.length;
      final available = ext.getAvailableRx(type).value.length;

      tabs.add(tabWidget(context, 'Installed $label', installed));
      tabs.add(tabWidget(context, 'Available $label', available));
    }

    if (ext.supportsAnime) addTabs(ItemType.anime, 'anime');
    if (ext.supportsManga) addTabs(ItemType.manga, 'manga');
    if (ext.supportsNovel) addTabs(ItemType.novel, 'novel');

    return tabs;
  }

  List<Widget> _buildTabViews(
    ColorScheme theme,
    ExtensionScreenBuilder builder,
  ) {
    final ext = manager;
    final query = _textEditingController.text;
    final lang = _selectedLanguage.value;

    List<Widget> views = [];

    void addViews(ItemType type) {
      final installed = ext.getInstalledRx(type).value;
      final available = ext.getAvailableRx(type).value;

      views.add(
        installed.isEmpty
            ? _emptyMessage('No installed ${type.name} extensions', theme)
            : builder(type, true, query, lang),
      );

      views.add(
        available.isEmpty
            ? _emptyMessage('No available ${type.name} extensions', theme)
            : builder(type, false, query, lang),
      );
    }

    if (ext.supportsAnime) addViews(ItemType.anime);
    if (ext.supportsManga) addViews(ItemType.manga);
    if (ext.supportsNovel) addViews(ItemType.novel);

    return views;
  }

  Widget _emptyMessage(String message, ColorScheme theme) {
    return Center(
      child: Text(
        message,
        style: TextStyle(color: theme.onSurface),
      ),
    );
  }
}

typedef ExtensionScreenBuilder = Widget Function(
  ItemType itemType,
  bool isInstalled,
  String searchQuery,
  String selectedLanguage,
);
