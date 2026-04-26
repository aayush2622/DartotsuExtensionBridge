import 'dart:convert';
import 'dart:io';

import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:http/http.dart' as http;

import '../Logger.dart';
import '../NetworkClient.dart';
import '../Settings/KvStore.dart';
import '../dartotsu_extension_bridge.dart';

abstract class DownloadablePlugin {
  String get name;
  String get remoteUrl;
  String get fileName;

  final RxBool installed = false.obs;
  final _client = MClient.init();

  String get _versionKey => "${name}_version";
  String get _updateKey => "${name}_has_update";

  final RxDouble progress = 0.0.obs;
  final RxBool downloading = false.obs;

  Future<Directory> get _dir async {
    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/plugins',
      useSystemPath: true,
      useCustomPath: false,
    );

    if (dir == null) throw Exception("Plugin dir null");

    await dir.create(recursive: true);
    return dir;
  }

  Future<File> get _file async {
    final dir = await _dir;
    return File("${dir.path}/$fileName");
  }

  Future<bool> isInstalled() async => (await _file).exists();

  Future<String> getPath() async {
    final file = await _file;
    return file.path;
  }

  bool get hasUpdate => getVal(_updateKey, defaultValue: false) ?? false;

  Future<void> download() async {
    if (await isInstalled() || downloading.value) return;

    downloading.value = true;
    progress.value = 0;

    Logger.log("Downloading $name plugin", show: true);

    try {
      final remote = await fetchRemote();

      await _download(
        remote["apk"],
        remote["versionCode"] ?? 0,
      );

      installed.value = true;
    } catch (e) {
      Logger.log("$name download failed: $e");
    } finally {
      downloading.value = false;
    }
  }

  Future<void> delete() async {
    final file = await _file;

    if (await file.exists()) {
      await file.delete();
      Logger.log("$name plugin deleted");
    }

    setVal(_versionKey, 0);
    setVal(_updateKey, false);
    installed.value = false;
  }

  Future<bool> checkForUpdate() async {
    if (!await isInstalled()) return false;

    final remote = await fetchRemote();

    final remoteVersion = remote["versionCode"] ?? 0;
    final localVersion = getVal<int>(_versionKey) ?? 0;

    final hasUpdate = remoteVersion > localVersion;

    setVal(_updateKey, hasUpdate);

    return hasUpdate;
  }

  Future<void> update() async {
    if (!await isInstalled()) return;

    final remote = await fetchRemote();

    final remoteVersion = remote["versionCode"] ?? 0;
    final localVersion = getVal<int>(_versionKey) ?? 0;

    if (remoteVersion <= localVersion) return;

    Logger.log("$name updating → v$remoteVersion", show: true);

    await _download(remote["apk"], remoteVersion);
    setVal(_updateKey, true);
  }

  Future<void> autoUpdate() async {
    if (!await isInstalled()) return;

    try {
      final hasUpdate = await checkForUpdate();
      if (hasUpdate) {
        await update();
      }
    } catch (e) {
      Logger.log("$name autoUpdate failed: $e");
    }
  }

  Map<String, dynamic>? _cachedMeta;

  Future<Map<String, dynamic>> fetchRemote() async {
    if (_cachedMeta != null) return _cachedMeta!;

    final res = await _client.get(Uri.parse(remoteUrl));
    if (res.statusCode != 200) {
      throw Exception("Failed to fetch metadata");
    }

    return _cachedMeta = jsonDecode(res.body);
  }

  String formatSize(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;

    if (bytes >= mb) return "${(bytes / mb).toStringAsFixed(1)} MB";
    if (bytes >= kb) return "${(bytes / kb).toStringAsFixed(1)} KB";
    return "$bytes B";
  }

  Future<void> _download(String url, int version) async {
    final request = http.Request("GET", Uri.parse(url));
    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw Exception("Download failed");
    }

    final file = await _file;
    final temp = File("${file.path}.tmp");

    final sink = temp.openWrite();

    int received = 0;
    final total = response.contentLength;

    await for (final chunk in response.stream) {
      received += chunk.length;
      sink.add(chunk);

      if (total != null && total > 0) {
        progress.value = received / total;
      }
    }

    await sink.flush();
    await sink.close();
    await temp.rename(file.path);

    setVal(_versionKey, version);
    progress.value = 1.0;

    Logger.log("$name plugin ready → v$version");
  }
}
