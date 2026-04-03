import 'dart:io';

import '../../Extensions/ExtensionSettings.dart';
import '../../Logger.dart';
import '../../dartotsu_extension_bridge.dart';
import '../Aniyomi/Models/Source.dart';
import 'AniyomiDesktopSourceMethods.dart';
import 'JniEngine.dart';

class AniyomiDesktopExtensions extends Extension {
  @override
  String get id => 'aniyomi_desktop';

  @override
  String get name => 'Aniyomi (Desktop)';

  @override
  bool get supportsNovel => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories =>
      (ASource, (source) => AniyomiSourceMethodsDesktop(source as ASource));

  final jni = JniChannel.instance;

  @override
  Future<void> onInitialize() async {
    await jni.init();
    var file = await DartotsuExtensionBridge.context.getDirectory();

    await jni.invokeMethod<void>(
      "initialize",
      {"path": file!.path},
    );
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    getInstalledRx(ItemType.anime).value =
        await _loadInstalled("getInstalledAnimeExtensions", ItemType.anime);
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    getInstalledRx(ItemType.manga).value =
        await _loadInstalled("getInstalledMangaExtensions", ItemType.manga);
  }

  Future<List<Source>> _loadInstalled(
    String method,
    ItemType type,
  ) async {
    try {
      final dir = await DartotsuExtensionBridge.context.getDirectory(
        subPath: 'aniyomi/extensions/${type.toString()}',
        useSystemPath: false,
        useCustomPath: true,
      );

      final result = await jni.invokeMethod<List<Map<String, dynamic>>>(
        method,
        {"path": dir!.path},
      );

      return result
          .map((e) => ASource.fromJson(e))
          .where((s) => s.itemType == type)
          .toList(growable: false);
    } catch (e, s) {
      Logger.log("Desktop loadInstalled error: $e\n$s");
      return [];
    }
  }

  @override
  Future<void> installSource(Source source) async {
    final s = source as ASource;

    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'aniyomi-extensions/${s.itemType}',
      useSystemPath: false,
      useCustomPath: true,
    );

    final file = File("${dir!.path}/${s.apkName}");

    if (s.apkUrl == null) {
      throw Exception("APK URL missing");
    }

    final bytes = await HttpClient()
        .getUrl(Uri.parse(s.apkUrl!))
        .then((r) => r.close())
        .then((r) => r.fold<List<int>>([], (a, b) => a..addAll(b)));

    await file.writeAsBytes(bytes);

    Logger.log("Installed desktop extension: ${s.pkgName}");

    switch (s.itemType) {
      case ItemType.anime:
        await fetchInstalledAnimeExtensions();
        break;
      case ItemType.manga:
        await fetchInstalledMangaExtensions();
        break;
      default:
        break;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as ASource;

    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'aniyomi-extensions/${s.itemType}',
      useSystemPath: false,
      useCustomPath: true,
    );

    final file = File("${dir!.path}/${s.apkName}");

    if (await file.exists()) {
      await file.delete();
      Logger.log("Deleted desktop extension: ${s.pkgName}");
    }

    switch (s.itemType) {
      case ItemType.anime:
        await fetchInstalledAnimeExtensions();
        break;
      case ItemType.manga:
        await fetchInstalledMangaExtensions();
        break;
      default:
        break;
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    await installSource(source);
  }

  /// ================= NO REPO LOGIC CHANGE =================

  @override
  Future<void> fetchAnimeExtensions() async {}

  @override
  Future<void> fetchMangaExtensions() async {}

  @override
  Future<void> fetchNovelExtensions() async {}

  @override
  Future<void> fetchInstalledNovelExtensions() async {}

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {}

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {}

  @override
  Set<String> get schemes => {"aniyomi", "tachiyomi"};

  @override
  void handleSchemes(Uri uri) {}

  @override
  List<ExtensionSetting> settings(context) => [];
}
