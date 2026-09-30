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
import '../IReaderSourceMethods.dart';
import 'Models/Source.dart';

class IReaderExtensions extends Extension
    with TachiyomiRepoBackend, AndroidApkInstallMixin {
  @override
  String get id => 'ireader';

  @override
  String get name => 'IReader';

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => false;

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/ireader.png";

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    ISource,
    (source) =>
        IReaderSourceMethods(source as ISource, MethodChannelBridge(platform)),
  );
  final _client = MClient.init();

  @override
  http.Client get repoClient => _client;

  @override
  List<Source> Function((Uint8List body, String repoUrl, ItemType type))
  get parseIndexIsolate => _parseExtensions;
  @override
  DownloadablePlugin plugin = IReaderPlugin();

  @override
  final platform = const MethodChannel('ireaderExtensionBridge');

  @override
  String get installPrivateKey => 'ireaderInstallPrivate';

  @override
  String get androidExtensionsDirName => 'ireader-extensions';

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
  Future<void> fetchInstalledNovelExtensions() async {
    await super.fetchInstalledNovelExtensions();

    novel.installed.value = await _loadInstalled(
      'getInstalledNovelExtensions',
      ItemType.novel,
    );
  }

  @override
  Future<void> fetchNovelExtensions() async {
    await super.fetchNovelExtensions();
    novel.available.value = await fetchExtensions(ItemType.novel);
  }

  @override
  Set<String> get schemes => {"ireader"};

  @override
  void handleSchemes(Uri uri) {
    final url = uri.queryParameters["url"];
    if (url != null && url.isNotEmpty) {
      addRepo(url, ItemType.novel);
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
        isChecked: getVal('ireaderInstallPrivate') ?? false,
        onSwitchChange: (value) => setVal('ireaderInstallPrivate', value),
        icon: Icons.lock_outline,
      ),
    ];
  }

  Future<List<Source>> _loadInstalled(String method, ItemType type) =>
      loadInstalledAndroidSources(method, type, ISource.fromJson);

  static List<ISource> _parseExtensions(
    (Uint8List body, String repoUrl, ItemType itemType) args,
  ) => parseTachiyomiIndexBytes<ISource>(
    args.$1,
    args.$2,
    args.$3,
    prefixes: const {'ireader: ': ItemType.novel},
    factory: _sourceFromEntry,
  );

  static ISource _sourceFromEntry(TachiyomiRepoEntry e) => ISource(
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

class IReaderPlugin extends DownloadablePlugin {
  @override
  String get name => "ireaderAndroid";

  @override
  String get fileName => "ireaderAndroid-plugin.apk";
}
