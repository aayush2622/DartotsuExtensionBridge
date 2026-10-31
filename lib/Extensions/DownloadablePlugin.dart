import 'dart:convert';
import 'dart:io';

import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../Logger.dart';
import 'ArchiveCheck.dart';
import 'InstallStep.dart';
import '../Network/MClient.dart';
import '../Settings/KvStore.dart';
import '../dartotsu_extension_bridge.dart';

abstract class DownloadablePlugin implements PluginDependency {
  String get name;
  String get fileName;

  final RxBool installed = false.obs;
  final RxBool availableInRepo = false.obs;
  final _client = MClient.init();

  String get _versionKey => "${name}_version";

  // iOS runs the desktop JARs unchanged in its embedded VM.
  static String get _platformKey =>
      Platform.isAndroid ? "android" : "desktopSplit";

  List<PluginDependency> get dependencies => const [];

  @override
  String get key => name;

  String get stepId => "plugin";

  late final InstallStep step = InstallStep(
    stepId,
    name,
    progress: progress,
    receivedBytes: receivedBytes,
    totalBytes: totalBytes,
    speed: speed,
  );

  late final RxList<InstallStep> _steps = <InstallStep>[step].obs;

  @override
  List<InstallStep> get steps => _steps;

  Future<bool> _needsUpdate(Map<String, dynamic> remote) async {
    final remoteVersion = remote["versionCode"] ?? 0;
    final localVersion = getVal<int>(_versionKey) ?? 0;
    if (remoteVersion > localVersion) return true;

    final remoteSize = remote["fileSize"];
    if (remoteSize is int && (await (await _file).length()) != remoteSize) {
      return true;
    }
    return !await _intact();
  }

  String? _checkedStamp;

  Future<bool> _intact() async {
    final file = await _file;
    if (!_isArchive(file.path) || !await file.exists()) return true;
    final stat = await file.stat();
    final stamp = "${stat.size}:${stat.modified.millisecondsSinceEpoch}";
    if (_checkedStamp == stamp) return true;
    if (await zipIsIntact(file.path)) {
      _checkedStamp = stamp;
      return true;
    }
    Logger.log("$name file is corrupt, it will be downloaded again");
    return false;
  }

  final RxBool updateAvailable = false.obs;

  static const _autoUpdateKey = "plugin_auto_update";

  static final RxBool autoUpdateEnabled = _autoUpdate();

  static RxBool _autoUpdate() {
    final flag = (getVal<bool>(_autoUpdateKey, defaultValue: true) ?? true).obs;
    flag.listen((v) => setVal(_autoUpdateKey, v));
    return flag;
  }

  final RxDouble progress = 0.0.obs;
  final RxBool downloading = false.obs;
  final RxnString error = RxnString();
  final RxInt receivedBytes = 0.obs;
  final RxInt totalBytes = 0.obs;
  final RxDouble speed = 0.0.obs;

  bool _cancelled = false;
  http.Client? _transfer;

  @override
  void cancel() {
    if (!downloading.value) return;
    _cancelled = true;
    _transfer?.close();
    for (final dependency in dependencies) {
      dependency.cancel();
    }
  }

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
    _indexFetchedAt = null;
  }

  static Future<List<Map<String, dynamic>>>? _loadingIndex;
  static DateTime? _indexFetchedAt;

  static const _indexFresh = Duration(seconds: 20);

  static bool get _indexIsStale {
    final fetched = _indexFetchedAt;
    return fetched == null || DateTime.now().difference(fetched) > _indexFresh;
  }

  static Future<List<Map<String, dynamic>>> _loadIndex(
    http.Client client, {
    bool forceRefresh = false,
  }) {
    final pending = _loadingIndex;
    if (pending != null) return pending;

    if (!forceRefresh && _cachedIndex != null) {
      return Future.value(_cachedIndex!);
    }

    return _loadingIndex =
        () async {
              final url = indexUrl;
              if (url.isEmpty) {
                throw Exception("No plugin index URL set");
              }

              final res = await client.get(Uri.parse(url));
              if (res.statusCode != 200) {
                throw Exception(
                  "Failed to fetch plugin index (${res.statusCode})",
                );
              }

              final decoded = jsonDecode(res.body);
              if (decoded is! List) {
                throw Exception("Plugin index is not a JSON array");
              }

              _indexFetchedAt = DateTime.now();
              return _cachedIndex = decoded.cast<Map<String, dynamic>>();
            }()
            .catchError((Object e) {
              final previous = _cachedIndex;
              if (previous == null) throw e;
              Logger.log("Plugin index refresh failed, using the last one: $e");
              return previous;
            })
            .whenComplete(() {
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

  Map<String, dynamic>? _cachedMeta;

  Future<Map<String, dynamic>?> fetchRemote({bool forceRefresh = false}) async {
    if (forceRefresh) _cachedMeta = null;
    if (_cachedMeta != null) return _cachedMeta;

    try {
      final entries = await DownloadablePlugin._loadIndex(
        _client,
        forceRefresh: forceRefresh && DownloadablePlugin._indexIsStale,
      );
      final named = entries.where((e) => e["name"] == name).toList();
      final entry = named.firstWhere(
        (e) => e["platform"] == _platformKey,
        orElse: () => named.firstWhere(
          (e) => e["platform"] == null,
          orElse: () => const {},
        ),
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

  Future<bool> download() async {
    if (await isInstalled() || downloading.value) return false;

    final remote = await fetchRemote();
    if (remote == null) {
      Logger.log("$name not found in plugin index", show: true);
      error.value = "$name is not in the plugin index";
      return false;
    }

    _begin();
    Logger.log("Downloading $name plugin", show: true);

    try {
      await _installDependencies(remote);
      await _download(remote["downloadUrl"], remote["versionCode"] ?? 0);
      installed.value = true;
      return true;
    } catch (e) {
      _fail(e);
      return false;
    } finally {
      _end();
    }
  }

  void _begin() {
    _cancelled = false;
    error.value = null;
    downloading.value = true;
    progress.value = 0;
    receivedBytes.value = 0;
    totalBytes.value = 0;
    speed.value = 0;
    step.state.value = StepStatus.waiting;
    step.error.value = null;
  }

  void _end() {
    _transfer?.close();
    _transfer = null;
    speed.value = 0;
    downloading.value = false;
  }

  void _fail(Object e) {
    Logger.log("$name download failed: $e");
    progress.value = 0;
    error.value = _cancelled ? null : _describe(e);
    if (step.active) {
      step.state.value = _cancelled ? StepStatus.waiting : StepStatus.failed;
      step.error.value = error.value;
    }
  }

  static String _describe(Object e) {
    final text = e.toString().replaceFirst("Exception: ", "");
    return text.isEmpty ? "Download failed" : text;
  }

  Future<void> delete() async {
    final file = await _file;

    if (await file.exists()) {
      await file.delete();
      Logger.log("$name plugin deleted");
    }

    setVal(_versionKey, 0);
    installed.value = false;
  }

  Future<bool> checkForUpdate({bool forceRefresh = false}) async {
    if (!await isInstalled()) return updateAvailable.value = false;

    final remote = await fetchRemote(forceRefresh: forceRefresh);
    if (remote == null) return updateAvailable.value = false;

    return updateAvailable.value = await _needsUpdate(remote);
  }

  /// Called after [update] has replaced the file, so whatever runs the old
  /// version can switch to the new one without an app restart.
  Future<void> Function()? onUpdated;

  Future<void> Function()? beforeSwap;

  Future<void> update() async {
    if (!await isInstalled() || downloading.value) return;

    final remote = await fetchRemote();
    if (remote == null) return;

    final own = await _needsUpdate(remote);
    if (!own && !await _dependenciesPending(remote)) return;

    final remoteVersion = remote["versionCode"] ?? 0;

    Logger.log("$name updating → v$remoteVersion", show: true);

    // download() reports progress via `downloading`/`progress`; update() ran
    // the exact same underlying transfer silently, so a UI observing those
    // two Rx values (e.g. a progress bar) never lit up for a background
    // update even though bytes were moving.
    _begin();

    try {
      await _installDependencies(remote);
      if (own) {
        await _download(remote["downloadUrl"], remoteVersion);
      } else {
        step.state.value = StepStatus.upToDate;
      }
      updateAvailable.value = false;
    } catch (e) {
      _fail(e);
      rethrow;
    } finally {
      _end();
    }

    if (!own) return;
    try {
      await onUpdated?.call();
    } catch (e) {
      Logger.log("$name could not switch to v$remoteVersion: $e");
    }
  }

  @override
  Future<void> autoUpdate() async {
    if (!await isInstalled()) return;

    try {
      if (autoUpdateEnabled.value) {
        for (final dependency in dependencies) {
          await dependency.autoUpdate();
        }
      }
      final hasUpdate = await checkForUpdate();
      if (hasUpdate && autoUpdateEnabled.value) {
        await update();
      }
    } catch (e) {
      Logger.log("$name autoUpdate failed: $e");
    }
  }

  Future<void>? _ensuring;

  @override
  Future<void> ensure({int minimum = 0, bool latest = false}) async {
    // a restart triggered by this plugin's own update must not wait on that install
    if (!latest && !downloading.value && await _satisfies(minimum)) {
      _settled();
      return;
    }

    while (_ensuring != null) {
      await _ensuring!.catchError((_) {});
    }

    // no await between the loop check and this claim, or two callers both install
    final job = _ensuring = _installIfNeeded(minimum, latest);
    try {
      await job;
    } finally {
      _ensuring = null;
    }
    if (!await _satisfies(minimum)) {
      throw Exception("$name v$minimum is not available");
    }
  }

  Future<void> _installIfNeeded(int minimum, bool latest) async {
    if (await _satisfies(minimum) && !(latest && await checkForUpdate())) {
      _settled();
      return;
    }
    await _installLatest();
  }

  void _settled() {
    if (step.active || step.state.value == StepStatus.done) return;
    step.state.value = StepStatus.upToDate;
    step.progress.value = 1;
  }

  Future<bool> _satisfies(int minimum) async {
    if (!await isInstalled()) return false;
    return (getVal<int>(_versionKey) ?? 0) >= minimum;
  }

  Future<void> _installLatest() async {
    while (downloading.value) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (await isInstalled()) {
      await update();
      return;
    }
    if (!await download()) {
      throw Exception(error.value ?? "$name could not be installed");
    }
  }

  int _minimumOf(PluginDependency dependency, Map<String, dynamic> remote) {
    final needs = remote["requires"];
    return needs is Map ? (needs[dependency.key] as num?)?.toInt() ?? 0 : 0;
  }

  Future<bool> _dependenciesPending(Map<String, dynamic> remote) async {
    for (final dependency in dependencies) {
      final planned = await dependency.plan(
        minimum: _minimumOf(dependency, remote),
      );
      if (planned.any((s) => !s.finished)) return true;
    }
    return false;
  }

  Future<void> _installDependencies(Map<String, dynamic> remote) async {
    for (final dependency in dependencies) {
      await dependency.ensure(
        minimum: _minimumOf(dependency, remote),
        latest: true,
      );
    }
  }

  @override
  Future<List<InstallStep>> plan({
    int minimum = 0,
    bool refresh = false,
  }) async {
    final remote = await fetchRemote(forceRefresh: refresh);
    final here = await isInstalled();
    final outdated =
        here &&
        remote != null &&
        (await _needsUpdate(remote) ||
            (getVal<int>(_versionKey) ?? 0) < minimum);
    final size = remote?["fileSize"];

    if (!step.active) {
      step.reset(
        to: here && !outdated ? StepStatus.upToDate : StepStatus.waiting,
        bytes: size is int ? size : 0,
        version: remote?["versionName"] as String?,
        replaces: outdated,
      );
    }

    final planned = <InstallStep>[];
    var pending = false;
    for (final dependency in dependencies) {
      final fromDependency = await dependency.plan(
        minimum: remote == null ? 0 : _minimumOf(dependency, remote),
        refresh: refresh,
      );
      pending = pending || fromDependency.any((s) => !s.finished);
      planned.addAll(fromDependency);
    }
    planned.add(step);
    _steps.assignAll(planned);
    updateAvailable.value = here && (outdated || pending);
    return planned;
  }

  Future<List<String>> installDependencies() async {
    if (dependencies.isEmpty) return const [];
    try {
      for (final dependency in dependencies) {
        await dependency.ensure();
      }
    } catch (e) {
      Logger.log("$name could not install what it needs: $e", show: true);
    }
    return [
      for (final dependency in dependencies) ...await dependency.classpath(),
    ];
  }

  @override
  Future<List<String>> classpath() async => [
    for (final dependency in dependencies) ...await dependency.classpath(),
    if (await isInstalled()) await getPath(),
  ];

  String formatSize(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;

    if (bytes >= mb) return "${(bytes / mb).toStringAsFixed(1)} MB";
    if (bytes >= kb) return "${(bytes / kb).toStringAsFixed(1)} KB";
    return "$bytes B";
  }

  static bool _isArchive(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.jar' || ext == '.apk' || ext == '.zip';
  }

  Future<void> _download(String url, int version) async {
    final file = await _file;
    final temp = File("${file.path}.tmp");

    final marker = File("${file.path}.tmp.version");
    if (await temp.exists()) {
      final started = await marker.exists() ? await marker.readAsString() : "";
      if (started.trim() != "$version") {
        Logger.log("Dropping a partial $name download from another version");
        await temp.delete();
      }
    }
    await marker.writeAsString("$version");

    int retries = 0;
    const maxRetries = 10;

    while (true) {
      var resumeFrom = await temp.exists() ? await temp.length() : 0;

      final request = http.Request("GET", Uri.parse(url));
      _transfer?.close();
      final client = _transfer = MClient.init();

      if (resumeFrom > 0) {
        request.headers["Range"] = "bytes=$resumeFrom-";
        Logger.log("Resuming $name from ${formatSize(resumeFrom)}");
      }

      step.state.value = StepStatus.downloading;
      step.error.value = null;

      try {
        final response = await client.send(request);

        if (response.statusCode != 200 && response.statusCode != 206) {
          final status = response.statusCode;
          final message = "Download failed ($status)";
          if (status >= 400 && status < 500 && status != 408 && status != 429) {
            throw _NoRetry(message);
          }
          throw Exception(message);
        }

        // A 200 means the server ignored our Range header and is streaming the
        // whole file from byte 0 — appending it to the existing partial would
        // corrupt the archive. Only a 206 is a genuine resume.
        final resuming = response.statusCode == 206 && resumeFrom > 0;
        if (!resuming) resumeFrom = 0;

        final sink = temp.openWrite(
          mode: resuming ? FileMode.append : FileMode.write,
        );

        int received = resumeFrom;
        var windowStart = DateTime.now();
        var windowBytes = 0;

        final int? total = resuming
            ? (response.contentLength == null
                  ? null
                  : resumeFrom + response.contentLength!)
            : response.contentLength;
        totalBytes.value = total ?? 0;
        receivedBytes.value = received;

        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            received += chunk.length;
            windowBytes += chunk.length;
            receivedBytes.value = received;

            final elapsed = DateTime.now().difference(windowStart);
            if (elapsed >= const Duration(milliseconds: 600)) {
              final rate = windowBytes / (elapsed.inMilliseconds / 1000);
              speed.value = speed.value == 0
                  ? rate
                  : speed.value * 0.6 + rate * 0.4;
              windowStart = DateTime.now();
              windowBytes = 0;
            }

            if (total != null && total > 0) {
              progress.value = received / total;
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }

        if (total != null && received < total) {
          throw Exception("Incomplete download");
        }

        step.state.value = StepStatus.installing;

        if (_isArchive(file.path) && !await zipIsIntact(temp.path)) {
          await temp.delete();
          throw Exception("Downloaded $name file is corrupt");
        }

        try {
          await beforeSwap?.call();
        } catch (e) {
          Logger.log(
            "$name beforeSwap failed, swapping in the update anyway: $e",
          );
        }

        try {
          await temp.rename(file.path);
        } on FileSystemException {
          // Windows won't rename onto an existing file, and rename() can
          // fail across filesystems - fall back to copy+delete. A crash
          // between these two calls at least leaves the correct bytes at
          // file.path (copy completed) rather than truncating it, which
          // await temp.copy(...); await temp.delete(); on its own already
          // achieves; the rename-first path just avoids the extra full
          // copy in the common case.
          await temp.copy(file.path);
          await temp.delete();
        }

        if (await marker.exists()) await marker.delete();
        setVal(_versionKey, version);
        progress.value = 1.0;
        step.state.value = StepStatus.done;

        Logger.log("$name:v$version installed", show: true);
        return;
      } catch (e) {
        if (_cancelled) throw Exception("Cancelled");
        if (e is _NoRetry) throw Exception(e.message);
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

class _NoRetry implements Exception {
  final String message;

  _NoRetry(this.message);
}
