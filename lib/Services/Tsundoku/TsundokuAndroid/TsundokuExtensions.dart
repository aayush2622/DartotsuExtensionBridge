import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:install_plugin/install_plugin.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../Extensions/DownloadablePlugin.dart';
import '../../../Extensions/ExtensionBridge.dart';
import '../../../Extensions/ExtensionSettings.dart';
import '../../../Logger.dart';
import '../../../NetworkClient.dart';
import '../../../Settings/KvStore.dart';
import '../../../dartotsu_extension_bridge.dart';
import '../../Network.dart';
import '../../Shared/TachiyomiRepo.dart';
import '../TsundokuSourceMethods.dart';
import 'Models/Source.dart';

class TsundokuExtensions extends Extension with TachiyomiRepoBackend {
  final _client = MClient.init();

  @override
  http.Client get repoClient => _client;

  @override
  List<Source> Function((Uint8List body, String repoUrl, ItemType type))
  get parseIndexIsolate => _parseExtensions;

  @override
  String get id => 'tsundoku';

  @override
  String get name => 'Tsundoku';

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => false;

  @override
  String get icon =>
      "packages/dartotsu_extension_bridge/assets/images/tsundoku.png";

  @override
  (Type, SourceMethods Function(Source)) get sourceMethodFactories => (
    TSource,
    (source) =>
        TsundokuSourceMethods(source as TSource, MethodChannelBridge(platform)),
  );

  @override
  DownloadablePlugin plugin = TsundokuPlugin();
  final platform = const MethodChannel('tsundokuExtensionBridge');

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

  final Map<String, Stream<double>> _installsInFlight = {};

  @override
  Stream<double> installSource(Source source) {
    final id = (source as TSource).id;

    // See the matching comment in Aniyomi's installSource - without this, a
    // double-tap (or install racing an update for the same source) runs two
    // independent download+write sequences concurrently against the same
    // target file. The stream is broadcast, so a concurrent caller shares
    // the same in-flight operation and progress.
    if (id != null) {
      final inFlight = _installsInFlight[id];
      if (inFlight != null) return inFlight;
    }

    final stream = progressStream((report) async {
      try {
        await _installSourceImpl(source, report);
      } finally {
        if (id != null) _installsInFlight.remove(id);
      }
    });

    if (id != null) {
      _installsInFlight[id] = stream;
    }

    return stream;
  }

  /// Streams [response] to [file], updating `installProgress[progressId]`
  /// (ambient GetX state) and calling [report] (this operation's own
  /// progress stream) as bytes arrive, once the content length is known.
  Future<void> _writeWithProgress(
    http.StreamedResponse response,
    File file,
    String? progressId,
    ItemType type,
    void Function(double) report,
  ) async {
    final sink = file.openWrite();
    final total = response.contentLength;
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;

        if (total != null && total > 0) {
          final fraction = received / total;
          if (progressId != null) {
            state(type).installProgress[progressId] = fraction;
          }
          report(fraction);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<void> _installSourceImpl(
    Source source,
    void Function(double) report,
  ) async {
    final aSource = source as TSource;
    final isPrivate = getVal('tsundokuInstallPrivate') ?? false;
    final type = source.itemType!;
    if (aSource.apkUrl == null) {
      throw Exception('Source APK URL is required for installation.');
    }

    final progressId = aSource.id;
    if (progressId != null) {
      state(type).installProgress[progressId] = 0.0;
    }

    try {
      final packageName =
          aSource.pkgName ??
          aSource.apkUrl!.split('/').last.replaceAll('.apk', '');

      final apkFileName = '$packageName.apk';

      final request = http.Request('GET', Uri.parse(aSource.apkUrl!));

      final response = await _client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Extension download failed (${response.statusCode})');
      }

      if (isPrivate) {
        final extDir = await DartotsuExtensionBridge.context.getDirectory(
          subPath: 'bridge/tsundoku-extensions/${aSource.itemType}',
          useSystemPath: false,
          useCustomPath: true,
        );

        if (extDir == null) {
          throw Exception('Failed to get extension directory');
        }

        await extDir.create(recursive: true);

        final file = File(path.join(extDir.path, apkFileName));

        await _writeWithProgress(response, file, progressId, type, report);

        Logger.log('Installed PRIVATE extension: ${aSource.pkgName}');
      } else {
        final tempDir = await getTemporaryDirectory();

        final apkFile = File(path.join(tempDir.path, apkFileName));

        await _writeWithProgress(response, apkFile, progressId, type, report);

        final result = await InstallPlugin.installApk(
          apkFile.path,
          appId: packageName,
        );

        if (await apkFile.exists()) {
          await apkFile.delete();
        }

        if (result['isSuccess'] != true) {
          throw Exception(
            'Installation failed: '
            '${result['errorMessage'] ?? 'Unknown error'}',
          );
        }

        Logger.log('Installed SHARED extension: $packageName');
      }

      final avail = state(type).available;

      avail.value = avail.value.where((e) => e.id != aSource.id).toList();
      await fetchInstalledExtensions(type);
      final raw = state(type).rawAvailable.value;
      detectUpdates(raw, type);
    } catch (e) {
      Logger.log('Error installing source: $e');
      rethrow;
    } finally {
      if (progressId != null) {
        state(type).installProgress.remove(progressId);
      }
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as TSource;
    final type = source.itemType!;
    // Resolve a package name without dereferencing a possibly-null apkUrl.
    final fallbackPkg =
        s.pkgName ??
        s.apkName?.replaceAll('.apk', '') ??
        s.apkUrl?.split('/').last.replaceAll('.apk', '') ??
        s.id ??
        '';
    try {
      if (s.isShared == false) {
        final baseDir = await DartotsuExtensionBridge.context.getDirectory(
          subPath: 'bridge/tsundoku-extensions/${type.toString()}',
          useSystemPath: false,
          useCustomPath: true,
        );

        final apkFileName = s.apkName ?? '$fallbackPkg.apk';
        final file = File(path.join(baseDir!.path, apkFileName));

        if (await file.exists()) {
          await file.delete();
          Logger.log('Deleted private extension: ${s.pkgName}');
        } else {
          Logger.log('Private extension file not found: ${s.pkgName}');
        }
        final raw = state(type).rawAvailable.value;
        final installed = state(type).installed.value;
        final installedIds = installed.map((e) => e.id).toSet();

        state(type).available.value = List.unmodifiable(
          raw.where((e) => !installedIds.contains(e.id)),
        );

        await fetchInstalledExtensions(type);
        detectUpdates(raw, type);
        return;
      }

      final packageName = s.pkgName;
      if (packageName == null || packageName.isEmpty) {
        throw Exception('Package name is required for uninstall.');
      }

      final isInstalled =
          await InstalledApps.isAppInstalled(packageName) ?? false;

      if (!isInstalled) {
        // The APK isn't actually present (install failed partway, or it was
        // removed outside the app) - still restore `available`/detectUpdates
        // the same way the two paths below do, instead of leaving the
        // source missing from both lists until an unrelated full refresh.
        state(type).installed.value = state(
          type,
        ).installed.value.where((e) => e.id != s.id).toList();

        final raw = state(type).rawAvailable.value;
        final installed = state(type).installed.value;
        final installedIds = installed.map((e) => e.id).toSet();

        state(type).available.value = List.unmodifiable(
          raw.where((e) => !installedIds.contains(e.id)),
        );

        await fetchInstalledExtensions(type);
        detectUpdates(raw, type);
        return;
      }

      final success = await InstalledApps.uninstallApp(packageName) ?? false;
      if (!success) {
        throw Exception('Failed to initiate uninstallation for: $packageName');
      }

      final timeout = const Duration(seconds: 10);
      final start = DateTime.now();

      while (DateTime.now().difference(start) < timeout) {
        final stillInstalled =
            await InstalledApps.isAppInstalled(packageName) ?? false;
        if (!stillInstalled) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final finalCheck =
          await InstalledApps.isAppInstalled(packageName) ?? false;
      if (finalCheck) {
        throw Exception('Uninstallation timed out or was cancelled by user.');
      }

      Logger.log('Uninstalled shared extension: $packageName');

      final raw = state(type).rawAvailable.value;
      final installed = state(type).installed.value;
      final installedIds = installed.map((e) => e.id).toSet();

      state(type).available.value = List.unmodifiable(
        raw.where((e) => !installedIds.contains(e.id)),
      );

      await fetchInstalledExtensions(type);
      detectUpdates(raw, type);
    } catch (e) {
      Logger.log('Error uninstalling source: $e');
      rethrow;
    }
  }

  @override
  Stream<double> updateSource(Source source) => installSource(source);

  @override
  Set<String> get schemes => {"tsundoku"};

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
        isChecked: getVal('tsundokuInstallPrivate') ?? false,
        onSwitchChange: (value) => setVal('tsundokuInstallPrivate', value),
        icon: Icons.lock_outline,
      ),
    ];
  }

  Future<List<Source>> _loadInstalled(String method, ItemType type) async {
    try {
      var path = await DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/tsundoku-extensions/${type.toString()}',
        useSystemPath: false,
        useCustomPath: true,
      );
      final jsonString = await platform.invokeMethod<String>(
        method,
        path?.path,
      );

      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> result = jsonDecode(jsonString);

      return result
          .map((e) => TSource.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.itemType == type)
          .toList(growable: false);
    } catch (e) {
      return [];
    }
  }

  static List<TSource> _parseExtensions(
    (Uint8List body, String repoUrl, ItemType itemType) args,
  ) => parseTachiyomiIndexBytes<TSource>(
    args.$1,
    args.$2,
    args.$3,
    prefixes: const {'Tsundoku: ': ItemType.novel},
    factory: _sourceFromEntry,
  );

  static TSource _sourceFromEntry(TachiyomiRepoEntry e) => TSource(
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

class TsundokuPlugin extends DownloadablePlugin {
  @override
  String get name => "tsundokuAndroid";

  @override
  String get fileName => "tsundokuAndroid-plugin.apk";
}
