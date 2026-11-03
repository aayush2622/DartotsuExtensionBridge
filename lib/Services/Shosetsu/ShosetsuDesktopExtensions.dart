import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../Engines/JavaEngine/Bridge/JavaBridge.dart';
import '../../Engines/JavaEngine/Bridge/JavaBridgeFactory.dart';
import '../../Extensions/DownloadablePlugin.dart';
import '../Shared/DesktopCorePlugin.dart';
import '../../Extensions/ExtensionBridge.dart';
import '../../Logger.dart';
import '../../Network/MClient.dart';
import '../../dartotsu_extension_bridge.dart';
import '../Shared/JvmBackend.dart';
import '../Shared/ShosetsuRepoBackend.dart';
import '../Shared/SimpleInstalledSourceStore.dart';
import 'ShosetsuSourceMethods.dart';
import 'Models/Source.dart';

class ShosetsuDesktopExtensions extends Extension
    with
        JvmBackend,
        DesktopJvmBackend,
        SimpleInstalledSourceStore<SsSource>,
        ShosetsuRepoBackend {
  @override
  String get name => Platform.isIOS ? 'Shosetsu' : 'Shosetsu (Desktop)';

  @override
  String get id => 'shosetsu_desktop';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/shosetsu.svg";

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => false;

  @override
  SsSource Function(Map<String, dynamic>) get sourceFromJson =>
      SsSource.fromJson;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    SsSource,
    (source) =>
        ShosetsuSourceMethods(source as SsSource, JavaExtensionBridge(java)),
  );

  @override
  DownloadablePlugin plugin = ShosetsuDesktopPlugin();

  @override
  final JavaBridge java = createJavaBridge();

  @override
  String get javaDataDir => 'shosetsu';

  final _client = MClient.init();

  @override
  http.Client get repoClient => _client;

  @override
  Future<Directory?> get extensionsDir =>
      DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/shosetsu/extensions/Novel',
        useSystemPath: false,
        useCustomPath: true,
      );

  @override
  Future<void> fetchInstalledNovelExtensions() async {
    await super.fetchInstalledNovelExtensions();
    try {
      final dir = await extensionsDir;
      final result = await java.call<List<Map<String, dynamic>>>(
        "getInstalledNovelExtensions",
        {"path": dir!.path},
      );

      novel.installed.value = result
          .map((e) => SsSource.fromJson(e))
          .toList(growable: false);
    } catch (e) {
      Logger.log("Error fetching installed Shosetsu Desktop extensions: $e");
    }
  }

  @override
  Future<void> fetchNovelExtensions() async {
    await super.fetchNovelExtensions();
    novel.available.value = await fetchExtensions(ItemType.novel);
  }

  @override
  Set<String> get schemes => {"shosetsu"};

  @override
  void handleSchemes(Uri uri) {
    final url = uri.queryParameters["url"];
    if (url != null && url.isNotEmpty) {
      addRepo(url, ItemType.novel);
    }
  }
}

class ShosetsuDesktopPlugin extends DesktopPlugin {
  @override
  String get name => "shosetsuDesktop";

  @override
  String get fileName => "shosetsuDesktop-plugin.jar";
}
