import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../Extensions/DownloadablePlugin.dart';
import '../../Extensions/ExtensionBridge.dart';
import '../../Logger.dart';
import '../../Network/MClient.dart';
import '../../dartotsu_extension_bridge.dart';
import '../Shared/JvmBackend.dart';
import '../Shared/ShosetsuRepoBackend.dart';
import '../Shared/SimpleInstalledSourceStore.dart';
import 'ShosetsuSourceMethods.dart';
import 'Models/Source.dart';

class ShosetsuExtensions extends Extension
    with
        JvmBackend,
        AndroidJvmBackend,
        SimpleInstalledSourceStore<SsSource>,
        ShosetsuRepoBackend {
  final _client = MClient.init();

  @override
  http.Client get repoClient => _client;

  @override
  String get id => 'shosetsu';

  @override
  String get name => 'Shosetsu';

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
    (source) => ShosetsuSourceMethods(
      source as SsSource,
      MethodChannelBridge(platform),
    ),
  );

  @override
  DownloadablePlugin plugin = ShosetsuPlugin();

  @override
  final platform = const MethodChannel('shosetsuExtensionBridge');

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
      final result = await platform.invokeMethod('getInstalledNovelExtensions', dir!.path);
      novel.installed.value = (result as List)
          .map((e) => SsSource.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (e) {
      Logger.log("Error fetching installed Shosetsu extensions: $e");
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

class ShosetsuPlugin extends DownloadablePlugin {
  @override
  String get name => "shosetsuAndroid";

  @override
  String get fileName => "shosetsuAndroid-plugin.apk";
}
