import 'dart:convert';
import 'dart:io';

import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../Logger.dart';
import '../NetworkClient.dart';
import '../Settings/KvStore.dart';
import '../dartotsu_extension_bridge.dart';

abstract class DownloadablePlugin {
  String get name;
  String get fileName;

  final RxBool installed = false.obs;
  final RxBool availableInRepo = false.obs;
  final _client = MClient.init();

  String get _versionKey => "${name}_version";
  String get _updateKey => "${name}_has_update";

  final RxDouble progress = 0.0.obs;
  final RxBool downloading = false.obs;

  static const _indexUrlKey = "plugin_index_url";

  static const _defaultIndexUrl =
      "https://raw.githubusercontent.com/aayush2622/DartotsuExtensionBridge/refs/heads/master/plugins.json";

  static String? _indexUrl;
  static List<Map<String, dynamic>>? _cachedIndex;

  static String get indexUrl => _indexUrl ??=
      (getVal<String>(_indexUrlKey, defaultValue: _defaultIndexUrl) ??
      _defaultIndexUrl);

  static void setIndexUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed == indexUrl) return;

    _indexUrl = trimmed;
    setVal(_indexUrlKey, trimmed);

    _cachedIndex = null;
  }

  static Future<List<Map<String, dynamic>>>? _loadingIndex;

  static Future<List<Map<String, dynamic>>> _loadIndex(http.Client client) {
    if (_cachedIndex != null) {
      return Future.value(_cachedIndex!);
    }

    return _loadingIndex ??=
        () async {
          final url = indexUrl;
          if (url.isEmpty) {
            throw Exception("No plugin index URL set");
          }

          final res = await client.get(Uri.parse(url));
          if (res.statusCode != 200) {
            throw Exception("Failed to fetch plugin index (${res.statusCode})");
          }

          final decoded = jsonDecode(res.body);
          if (decoded is! List) {
            throw Exception("Plugin index is not a JSON array");
          }

          _cachedIndex = decoded.cast<Map<String, dynamic>>();
          return _cachedIndex!;
        }().whenComplete(() {
          _loadingIndex = null;
        });
  }
  // ---------------------------------------------------------------------

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
    return File(p.join(dir.path, fileName));
  }

  Future<bool> isInstalled() async => (await _file).exists();

  Future<String> getPath() async {
    final file = await _file;
    return file.path;
  }

  bool get hasUpdate => getVal(_updateKey, defaultValue: false) ?? false;

  Map<String, dynamic>? _cachedMeta;

  Future<Map<String, dynamic>?> fetchRemote({bool forceRefresh = false}) async {
    if (forceRefresh) _cachedMeta = null;
    if (_cachedMeta != null) return _cachedMeta;

    try {
      final entries = await DownloadablePlugin._loadIndex(_client);
      final entry = entries.firstWhere(
        (e) => e["name"] == name,
        orElse: () => const {},
      );

      if (entry.isEmpty) {
        availableInRepo.value = false;
        return _cachedMeta = null;
      }

      availableInRepo.value = true;
      return _cachedMeta = entry;
    } catch (e) {
      Logger.log("$name index lookup failed: $e");
      availableInRepo.value = false;
      return _cachedMeta = null;
    }
  }

  Future<bool> checkAvailability() async {
    final remote = await fetchRemote(forceRefresh: true);
    return remote != null;
  }

  Future<void> download() async {
    if (await isInstalled() || downloading.value) return;

    final remote = await fetchRemote();
    if (remote == null) {
      Logger.log("$name not found in plugin index", show: true);
      return;
    }

    downloading.value = true;
    progress.value = 0;

    Logger.log("Downloading $name plugin", show: true);

    try {
      await _download(remote["downloadUrl"], remote["versionCode"] ?? 0);
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
    if (remote == null) return false;

    final remoteVersion = remote["versionCode"] ?? 0;
    final localVersion = getVal<int>(_versionKey) ?? 0;

    final hasUpdate = remoteVersion > localVersion;

    setVal(_updateKey, hasUpdate);

    return hasUpdate;
  }

  Future<void> update() async {
    if (!await isInstalled()) return;

    final remote = await fetchRemote();
    if (remote == null) return;

    final remoteVersion = remote["versionCode"] ?? 0;
    final localVersion = getVal<int>(_versionKey) ?? 0;

    if (remoteVersion <= localVersion) return;

    Logger.log("$name updating → v$remoteVersion", show: true);

    await _download(remote["downloadUrl"], remoteVersion);
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

  String formatSize(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;

    if (bytes >= mb) return "${(bytes / mb).toStringAsFixed(1)} MB";
    if (bytes >= kb) return "${(bytes / kb).toStringAsFixed(1)} KB";
    return "$bytes B";
  }

  Future<void> _download(String url, int version) async {
    final file = await _file;
    final temp = File("${file.path}.tmp");

    int retries = 0;
    const maxRetries = 10;

    while (true) {
      final downloaded = await temp.exists() ? await temp.length() : 0;

      final request = http.Request("GET", Uri.parse(url));

      if (downloaded > 0) {
        request.headers["Range"] = "bytes=$downloaded-";
        Logger.log("Resuming $name from ${formatSize(downloaded)}");
      }

      try {
        final response = await _client.send(request);

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception("Download failed (${response.statusCode})");
        }

        final sink = temp.openWrite(
          mode: downloaded > 0 ? FileMode.append : FileMode.write,
        );

        int received = downloaded;

        int? total;
        if (response.statusCode == 206) {
          total = response.contentLength == null
              ? null
              : downloaded + response.contentLength!;
        } else {
          total = response.contentLength;
        }

        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;

          if (total != null && total > 0) {
            progress.value = received / total;
          }
        }

        await sink.flush();
        await sink.close();

        if (total != null && received < total) {
          throw Exception("Incomplete download");
        }

        await temp.copy(file.path);
        await temp.delete();

        setVal(_versionKey, version);
        progress.value = 1.0;

        Logger.log("$name:v$version installed", show: true);
        return;
      } catch (e) {
        retries++;

        Logger.log("$name download interrupted ($retries/$maxRetries): $e");

        if (retries >= maxRetries) {
          rethrow;
        }

        await Future.delayed(Duration(seconds: retries.clamp(1, 5)));
      }
    }
  }
}
