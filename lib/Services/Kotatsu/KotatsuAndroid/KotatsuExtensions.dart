import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../../Shared/KotatsuRepoBackend.dart';
import '../KotatsuSourceMethods.dart';

class KotatsuExtensions extends Extension
    with KotatsuRepoBackend<KotatsuSource> {
  @override
  String get activeSourcesKey => 'kotatsu_active_sources';

  final platform = const MethodChannel('kotatsuExtensionBridge');

  @override
  String get id => 'kotatsu';

  @override
  String get name => 'Kotatsu';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/kotatsu.png";

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsNovel => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    KotatsuSource,
    (source) => KotatsuSourceMethods(
      source as KotatsuSource,
      MethodChannelBridge(platform),
    ),
  );

  @override
  DownloadablePlugin plugin = KotatsuPlugin();

  @override
  Future<bool> onInitialize() async {
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    unawaited(plugin.autoUpdate());

    final filePath = await plugin.getPath();
    await platform.invokeMethod('loadPlugin', {"path": filePath});
    await BridgeChannels.init();

    final network = DartotsuExtensionBridge.context.network;
    if (network != null) {
      await platform.invokeMethod(
        'initClient',
        jsonEncode({
          'dns': network.dns,
          'proxy': network.proxy,
          'userAgent': network.userAgent,
        }),
      );
    }
    return true;
  }

  @override
  Future<Directory?> get sourcesDir =>
      DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/kotatsu',
        useSystemPath: false,
        useCustomPath: true,
      );

  @override
  Future<List<KotatsuSource>> loadInstalledFromNative(Directory dir) async {
    final jsonString = await platform.invokeMethod<String>(
      'getInstalledMangaExtensions',
      dir.path,
    );
    if (jsonString == null || jsonString.isEmpty) return const [];

    final List<dynamic> result = jsonDecode(jsonString);
    return result
        .map((e) => KotatsuSource.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }
}

class KotatsuPlugin extends DownloadablePlugin {
  @override
  String get name => "kotatsuAndroid";

  @override
  String get fileName => "kotatsuAndroid-plugin.apk";
}
