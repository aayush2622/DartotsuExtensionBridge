import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../Engines/JavaEngine/Bridge/JavaBridgeFactory.dart';
import '../../../Engines/JavaEngine/Bridge/JniBridge.dart';
import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../../Shared/KotatsuRepoBackend.dart';
import '../KotatsuSourceMethods.dart';

class KotatsuDesktopExtensions extends Extension
    with KotatsuRepoBackend<KotatsuDesktopSource> {
  @override
  String get activeSourcesKey => 'kotatsu_desktop_active_sources';

  @override
  String get id => 'kotatsu_desktop';

  @override
  String get name => 'Kotatsu (Desktop)';

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
      JniExtensionBridge(jni),
    ),
  );

  @override
  DownloadablePlugin plugin = KotatsuDesktopPlugin();

  final JavaBridge jni = createJavaBridge();

  final _context = DartotsuExtensionBridge.context;

  @override
  Future<bool> onInitialize() async {
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    unawaited(plugin.autoUpdate());

    final filePath = await plugin.getPath();

    await BridgeChannels.init();
    await jni.init(pluginJarPath: filePath);

    final dir = await sourcesDir;
    await jni.call<void>("initializeDesktop", {"path": dir!.path});

    if (_context.network != null) {
      await jni.call<void>("initClient", {
        "data": jsonEncode({
          'dns': _context.network?.dns,
          'proxy': _context.network?.proxy,
          'userAgent': _context.network?.userAgent,
        }),
      });
    }
    return true;
  }

  @override
  void dispose() async {
    super.dispose();
    jni.dispose();
  }

  @override
  Future<Directory?> get sourcesDir => _context.getDirectory(
    subPath: 'bridge/kotatsu',
    useSystemPath: false,
    useCustomPath: true,
  );

  @override
  Future<List<KotatsuDesktopSource>> loadInstalledFromNative(
    Directory dir,
  ) async {
    final result = await jni.call<List<Map<String, dynamic>>>(
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
