import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Extensions/ExtensionSettings.dart';
import '../../../NetworkClient.dart';
import '../../../Settings/KvStore.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../../Shared/AndroidApkInstallMixin.dart';
import '../../Shared/TachiyomiRepo.dart';
import '../AniyomiSourceMethods.dart';
import 'Models/Source.dart';

class AniyomiExtensions extends Extension
    with TachiyomiRepoBackend, AndroidApkInstallMixin {
  final _client = MClient.init();

  @override
  http.Client get repoClient => _client;

  @override
  List<Source> Function((Uint8List body, String repoUrl, ItemType type))
  get parseIndexIsolate => _parseExtensions;

  @override
  String get id => 'aniyomi';

  @override
  String get name => 'Aniyomi';

  @override
  bool get supportsNovel => false;

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/aniyomi.png";

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    ASource,
    (source) =>
        AniyomiSourceMethods(source as ASource, MethodChannelBridge(platform)),
  );

  @override
  DownloadablePlugin plugin = AniyomiPlugin();

  @override
  final platform = const MethodChannel('aniyomiExtensionBridge');

  @override
  String get installPrivateKey => 'aniyomiInstallPrivate';

  @override
  String get androidExtensionsDirName => 'aniyomi-extensions';

  @override
  Future<bool> onInitialize() async {
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    unawaited(plugin.autoUpdate());

    final filePath = await plugin.getPath();

    await platform.invokeMethod('loadPlugin', {"path": filePath});
    await BridgeChannels.init();
    var context = DartotsuExtensionBridge.context;
    if (context.network != null) {
      await platform.invokeMethod(
        'initClient',
        jsonEncode({
          'dns': context.network?.dns,
          'proxy': context.network?.proxy,
          'userAgent': context.network?.userAgent,
        }),
      );
    }
    return true;
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    await super.fetchInstalledAnimeExtensions();

    anime.installed.value = await _loadInstalled(
      'getInstalledAnimeExtensions',
      ItemType.anime,
    );
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    await super.fetchInstalledMangaExtensions();

    manga.installed.value = await _loadInstalled(
      'getInstalledMangaExtensions',
      ItemType.manga,
    );
  }

  @override
  Future<void> fetchAnimeExtensions() async {
    await super.fetchAnimeExtensions();
    anime.available.value = await fetchExtensions(ItemType.anime);
  }

  @override
  Future<void> fetchMangaExtensions() async {
    await super.fetchMangaExtensions();
    manga.available.value = await fetchExtensions(ItemType.manga);
  }

  @override
  Set<String> get schemes => {"aniyomi", "tachiyomi"};

  @override
  void handleSchemes(Uri uri) {
    final url = uri.queryParameters["url"];
    if (url != null && url.isNotEmpty) {
      addRepo(url, uri.scheme == "aniyomi" ? ItemType.anime : ItemType.manga);
    }
  }

  @override
  List<ExtensionSetting> settings(BuildContext context) {
    return [
      ExtensionSetting(
        name: "Install Extensions Privately",
        description:
            "Install extensions in a private directory (extensions won't be visible to other apps)",
        type: ExtensionSettingType.switchType,
        isChecked: getVal('aniyomiInstallPrivate') ?? false,
        onSwitchChange: (value) => setVal('aniyomiInstallPrivate', value),
        icon: Icons.lock_outline,
      ),
    ];
  }

  Future<List<Source>> _loadInstalled(String method, ItemType type) =>
      loadInstalledAndroidSources(method, type, ASource.fromJson);

  static List<ASource> _parseExtensions(
    (Uint8List body, String repoUrl, ItemType itemType) args,
  ) => parseTachiyomiIndexBytes<ASource>(
    args.$1,
    args.$2,
    args.$3,
    prefixes: const {
      'Aniyomi: ': ItemType.anime,
      'Tachiyomi: ': ItemType.manga,
    },
    factory: _sourceFromEntry,
  );

  static ASource _sourceFromEntry(TachiyomiRepoEntry e) => ASource(
    id: e.id,
    name: e.name,
    pkgName: e.pkgName,
    apkName: e.apkName,
    lang: e.lang,
    version: e.version,
    isNsfw: e.isNsfw,
    itemType: e.itemType,
    repo: e.repo,
    iconUrl: e.iconUrl,
    apkUrlOverride: e.apkUrl,
    jarUrl: e.jarUrl,
  );
}

class AniyomiPlugin extends DownloadablePlugin {
  @override
  String get name => "aniyomiAndroid";

  @override
  String get fileName => "aniyomiAndroid-plugin.apk";
}
