import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Logger.dart';
import '../../../NetworkClient.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../../Shared/CloudStreamRepoBackend.dart';
import '../CloudStreamSourceMethods.dart';
import 'Models/CloudStreamSource.dart';

class CloudStreamExtensions extends Extension
    with CloudStreamRepoBackend<CSource> {
  @override
  String get id => 'cloudstream';

  @override
  String get name => 'CloudStream';

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/cloudstream.png";

  @override
  bool get supportsNovel => false;

  @override
  bool get supportsManga => false;

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    CSource,
    (source) => CloudStreamSourceMethods(
      source as CSource,
      MethodChannelBridge(platform),
    ),
  );

  @override
  DownloadablePlugin plugin = CloudStreamPlugin();

  static const platform = MethodChannel('cloudStreamExtensionBridge');
  final _client = MClient.init();

  @override
  http.Client get repoClient => _client;

  @override
  Future<Directory?> get extensionsDir => DartotsuExtensionBridge.context
      .getDirectory(
        subPath: 'bridge/cloudStream/extensions/Anime',
        useSystemPath: false,
        useCustomPath: true,
      );

  @override
  List<Source> Function((String body, String repoUrl, ItemType type))
  get parseExtensionsIsolate => _parseExtensions;

  final _context = DartotsuExtensionBridge.context;
  @override
  Future<bool> onInitialize() async {
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    unawaited(plugin.autoUpdate());

    final filePath = await plugin.getPath();

    await platform.invokeMethod('loadPlugin', {"path": filePath});
    await BridgeChannels.init();
    if (_context.network != null) {
      await platform.invokeMethod(
        'initClient',
        jsonEncode({
          'dns': _context.network?.dns,
          'proxy': _context.network?.proxy,
          'userAgent': _context.network?.userAgent,
        }),
      );
    }
    return true;
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    await super.fetchInstalledAnimeExtensions();
    try {
      final dir = await _context.getDirectory(
        subPath: 'bridge/cloudStream/extensions/Anime',
        useSystemPath: false,
        useCustomPath: true,
      );
      final jsonString = await platform.invokeMethod<String>(
        "getInstalledAnimeExtensions",
        dir?.path,
      );

      if (jsonString == null || jsonString.isEmpty) {
        return;
      }

      final List<dynamic> result = jsonDecode(jsonString);
      anime.installed.value = result
          .map((e) => CSource.fromJson(e))
          .toList(growable: false);
    } catch (e) {
      Logger.log("Error fetching installed CloudStream Desktop extensions: $e");
    }
  }

  @override
  Future<void> fetchAnimeExtensions() async {
    await super.fetchAnimeExtensions();
    anime.available.value = await fetchExtensions(ItemType.anime);
  }

  static List<CSource> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) => parseCloudStreamRepoBody<CSource>(args.$1, args.$2, _sourceFromEntry);

  static CSource _sourceFromEntry(CloudStreamRepoEntry e) => CSource(
    id: e.id,
    name: e.name,
    baseUrl: e.baseUrl,
    lang: e.lang,
    iconUrl: e.iconUrl,
    isNsfw: e.isNsfw,
    version: e.version,
    versionLast: e.version,
    itemType: ItemType.anime,
    repo: e.repo,
    internalName: e.internalName,
    pluginUrl: e.pluginUrl,
  );
}

class CloudStreamPlugin extends DownloadablePlugin {
  @override
  String get name => "cloudStreamAndroid";

  @override
  String get fileName => "cloudStreamAndroid-plugin.apk";
}
