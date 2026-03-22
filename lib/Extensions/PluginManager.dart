import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../Logger.dart';
import '../../Settings/KvStore.dart';
import '../../dartotsu_extension_bridge.dart';
import '../NetworkClient.dart';

/// Plugins are distributed as standalone APKs to:
/// - Reduce base app size
class PluginManager {
  final _client = MClient.init();
  final String pluginName;
  late String remoteUrl;

  PluginManager(
    this.pluginName, {
    String? remoteUrl,
  }) : remoteUrl = remoteUrl ??
            "https://raw.githubusercontent.com/aayush2622/DartotsuExtensionBridge/master/androidExtensionManagers/builds/$pluginName/$pluginName-plugin.json";

  String get pluginFileName => "${pluginName}_plugin.apk";

  String get pluginVersionKey => "${pluginName}PluginVersion";

  String get pluginHasUpdateKey => "${pluginName}PluginHasUpdate";

  /// Behavior:
  /// - If plugin already exists:
  ///   - Returns immediately with current path
  ///   - Triggers background update check (non-blocking)
  ///
  /// - If plugin does NOT exist:
  ///   - Fetches metadata
  ///   - Downloads APK
  ///   - Stores version
  ///
  /// Returns:
  /// - path → local file path of plugin APK
  /// - hasUpdate → whether a newer version was detected
  Future<(String path, bool hasUpdate)> ensurePlugin() async {
    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'plugins',
      useSystemPath: true,
      useCustomPath: false,
    );

    if (dir == null) throw Exception("Failed to get plugin dir");

    await dir.create(recursive: true);

    final file = File("${dir.path}/$pluginFileName");

    final exists = await file.exists();
    final hasUpdate = getVal<bool>(pluginHasUpdateKey) ?? false;

    if (exists) {
      unawaited(_checkForUpdateInBackground(file));
      return (file.path, hasUpdate);
    }

    Logger.log("Downloading $pluginName plugin", show: true);

    final remote = await _fetchRemoteInfo();

    await _downloadAndReplace(
      file,
      remote["apk"],
      remote["versionCode"] ?? 0,
    );

    return (file.path, true);
  }

  Future<void> _checkForUpdateInBackground(File file) async {
    try {
      final remote = await _fetchRemoteInfo();

      final remoteVersion = remote["versionCode"] ?? 0;
      final apkUrl = remote["apk"];
      final localVersion = getVal<int>(pluginVersionKey) ?? 0;

      if (remoteVersion > localVersion) {
        Logger.log(
          "$pluginName update found → v$remoteVersion",
          show: true,
        );

        final tempFile = File("${file.path}.tmp");

        final res = await _client.get(Uri.parse(apkUrl));
        if (res.statusCode != 200) return;

        await tempFile.writeAsBytes(res.bodyBytes);
        await tempFile.rename(file.path);

        setVal(pluginVersionKey, remoteVersion);
        setVal(pluginHasUpdateKey, true);
      } else {
        setVal(pluginHasUpdateKey, false);
      }
    } catch (e) {
      Logger.log("Background update failed: $e");
    }
  }

  Future<void> _downloadAndReplace(
    File file,
    String url,
    int version,
  ) async {
    final res = await _client.get(Uri.parse(url));

    if (res.statusCode != 200) {
      throw Exception("Download failed");
    }

    final tempFile = File("${file.path}.tmp");
    await tempFile.writeAsBytes(res.bodyBytes);
    await tempFile.rename(file.path);

    setVal(pluginVersionKey, version);

    Logger.log("$pluginName plugin downloaded → v$version");
  }

  Future<Map<String, dynamic>> _fetchRemoteInfo() async {
    final res = await _client.get(Uri.parse(remoteUrl));

    if (res.statusCode != 200) {
      throw Exception("Failed to fetch plugin metadata");
    }

    return jsonDecode(res.body);
  }
}
