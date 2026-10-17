import 'dart:async';
import 'dart:io';

import '../../../Engines/JavaEngine/Bridge/JavaBridgeFactory.dart';
import '../../../Engines/JavaEngine/Bridge/JavaBridge.dart';
import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Shared/JvmBackend.dart';
import '../../Shared/KotatsuRepoBackend.dart';
import '../KotatsuSourceMethods.dart';

class KotatsuDesktopExtensions extends Extension
    with JvmBackend, DesktopJvmBackend, KotatsuRepoBackend<KotatsuDesktopSource> {
  @override
  String get activeSourcesKey => 'kotatsu_desktop_active_sources';

  @override
  String get id => 'kotatsu_desktop';

  @override
  String get name => Platform.isIOS ? 'Kotatsu' : 'Kotatsu (Desktop)';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/kotatsu.png";

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsNovel => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    KotatsuDesktopSource,
    (source) => KotatsuSourceMethods(
      source as KotatsuDesktopSource,
      JavaExtensionBridge(java),
    ),
  );

  @override
  DownloadablePlugin plugin = KotatsuDesktopPlugin();

  @override
  final JavaBridge java = createJavaBridge();




  @override
  String get javaDataDir => 'kotatsu';

  @override
  Future<Directory?> get javaDataDirectory => sourcesDir;

  @override
  Future<Directory?> get sourcesDir => DartotsuExtensionBridge.context.getDirectory(
    subPath: 'bridge/kotatsu',
    useSystemPath: false,
    useCustomPath: true,
  );

  @override
  Future<List<KotatsuDesktopSource>> loadInstalledFromNative(
    Directory dir,
  ) async {
    final result = await java.call<List<Map<String, dynamic>>>(
      'getInstalledMangaExtensions',
      {'path': dir.path},
    );

    return result
        .map((e) => KotatsuDesktopSource.fromJson(e))
        .toList(growable: false);
  }
}

class KotatsuDesktopPlugin extends DownloadablePlugin {
  @override
  String get name => "kotatsuDesktop";

  @override
  String get fileName => "kotatsuDesktop-plugin.jar";
}
