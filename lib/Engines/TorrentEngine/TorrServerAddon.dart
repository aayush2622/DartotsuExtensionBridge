import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../ExtensionBridge.dart';
import '../../Extensions/Addon.dart';
import '../../Logger.dart';
import '../../Network/MClient.dart';
import '../../Settings/KvStore.dart';
import 'Models/TorrentInfo.dart';
import 'TorrServerController.dart';
import 'TorrServerControllerIos.dart';
import 'TorrServerControllerSubprocess.dart';

/// Downloads and installs the TorrServer binary for Windows, Linux, macOS,
/// and Android at app runtime.
///
/// iOS embeds `TorrServerKit.xcframework` at build time instead, so it's not
/// installable through this addon; use [TorrServerControllerIos] directly
/// there. Everywhere else, [binaryPath] hands back a plain downloaded file —
/// how it actually gets invoked (subprocess exec, dlopen/FFI, ...) is up to
/// the caller.
class TorrServerAddon extends Addon {
  final _client = MClient.download();

  TorrServerController? _controller;
  String? _activeHash;

  TorrServerAddon();

  static const _streamableExtensions = {
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.webm',
    '.m4v',
    '.flv',
    '.wmv',
    '.ts',
    '.mp3',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
    '.wav',
  };

  /// Starts (if not already running) and returns the shared [TorrServerController].
  Future<TorrServerController> ensureStarted() async {
    final controller = _controller ??= Platform.isIOS
        ? TorrServerControllerIos()
        : TorrServerControllerSubprocess();

    if (!controller.isRunning) {
      await controller.start(customBinaryPath: await binaryPath);
    }

    return controller;
  }

  Future<String>? _startStreamFuture;

  /// Convenience wrapper mirroring the old libtorrent addon's `startStream`:
  /// adds [url] (a magnet URI, an `http(s)://` link to a `.torrent` file, or a
  /// local `.torrent` file path), waits for its metadata, picks the largest
  /// streamable file, and returns the playable HTTP stream URL for it. Only
  /// one stream is kept active at a time — a prior one is stopped first.
  Future<String> startStream({
    required String url,
    String? title,
    String? category,
    String? poster,
  }) {
    // Without this, two concurrent startStream() calls both pass
    // stopStream() and both add a torrent; whichever finishes last
    // overwrites _activeHash, silently orphaning the loser's torrent (and
    // its downloaded cache) on the server until the whole controller stops.
    final inFlight = _startStreamFuture;
    if (inFlight != null) return inFlight;

    final future = _startStreamImpl(
      url: url,
      title: title,
      category: category,
      poster: poster,
    );
    return _startStreamFuture = future.whenComplete(
      () => _startStreamFuture = null,
    );
  }

  Future<String> _startStreamImpl({
    required String url,
    String? title,
    String? category,
    String? poster,
  }) async {
    final controller = await ensureStarted();
    await stopStream();

    final added = await _addTorrent(
      controller,
      url: url,
      title: title,
      category: category,
      poster: poster,
    );

    _activeHash = added.hash;

    final info = await _waitForMetadata(controller, added.hash);
    final selected = _selectStreamableFile(info);

    if (selected == null) {
      throw Exception("No streamable file found in torrent.");
    }

    return controller.streamUrl(info.hash, fileIndex: selected.id).toString();
  }

  Future<TorrentInfo> _addTorrent(
    TorrServerController controller, {
    required String url,
    String? title,
    String? category,
    String? poster,
  }) async {
    if (url.startsWith("magnet:")) {
      return controller.addTorrent(
        magnet: url,
        title: title,
        category: category,
        poster: poster,
      );
    }
    if (url.startsWith("http://") || url.startsWith("https://")) {
      final torrentFile = await _downloadTorrentFile(url);
      try {
        return await controller.addTorrent(
          torrentFile: await torrentFile.readAsBytes(),
          title: title,
          category: category,
          poster: poster,
        );
      } finally {
        if (await torrentFile.exists()) {
          await torrentFile.delete();
        }
      }
    }
    return controller.addTorrent(
      torrentFile: await File(url).readAsBytes(),
      title: title,
      category: category,
      poster: poster,
    );
  }

  /// Adds a torrent for downloading without touching the stream started by
  /// [startStream]. Returns the torrent once its file list is known; read the
  /// files from [TorrentInfo.fileStats] and fetch one with [fileUrl]. Call
  /// [release] when done.
  Future<TorrentInfo> addForDownload({
    required String url,
    String? title,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final controller = await ensureStarted();
    final added = await _addTorrent(controller, url: url, title: title);
    return _waitForMetadata(controller, added.hash, timeout: timeout);
  }

  /// HTTP url of one file of a torrent added with [addForDownload]. The server
  /// answers range requests, so it can be fetched and resumed like any file.
  Uri fileUrl(String hash, int fileIndex) {
    final controller = _controller;
    if (controller == null) {
      throw StateError("TorrServer is not running");
    }
    return controller.streamUrl(hash, fileIndex: fileIndex);
  }

  Future<TorrentInfo> torrentInfo(String hash) async =>
      (await ensureStarted()).getTorrent(hash);

  /// Picks the file of [info] that best matches [episode]: the one whose name
  /// carries that number, otherwise the biggest streamable file.
  TorrentFileStat? pickFile(TorrentInfo info, {double? episode}) {
    final candidates = [
      for (final file in info.fileStats)
        if (_streamableExtensions.contains(
          p.extension(file.path).toLowerCase(),
        ))
          file,
    ];
    if (candidates.isEmpty) return null;
    if (episode != null && candidates.length > 1) {
      final wanted = RegExp.escape(
        episode % 1 == 0 ? episode.toInt().toString() : "$episode",
      );
      final pattern = RegExp("(?<![0-9.])0*$wanted(?![0-9])");
      final tags = RegExp(r"\[[^\]]*\]|\([^)]*\)");
      for (final file in candidates) {
        final name = p
            .basenameWithoutExtension(file.path)
            .replaceAll(tags, " ");
        if (pattern.hasMatch(name)) return file;
      }
    }
    return _selectStreamableFile(info);
  }

  Future<void> release(String hash) async {
    try {
      await _controller?.removeTorrent(hash);
    } catch (_) {}
  }

  /// Removes the currently active torrent (added by [startStream]) and its
  /// cached data, if any.
  Future<void> stopStream() async {
    final hash = _activeHash;
    _activeHash = null;
    if (hash == null) return;

    try {
      await _controller?.removeTorrent(hash);
    } catch (_) {}
  }

  Future<TorrentInfo> _waitForMetadata(
    TorrServerController controller,
    String hash, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final info = await controller.getTorrent(hash);
      if (info.fileStats.isNotEmpty) return info;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    throw Exception(
      "Timed out waiting for torrent metadata (${timeout.inSeconds}s)",
    );
  }

  TorrentFileStat? _selectStreamableFile(TorrentInfo info) {
    TorrentFileStat? selected;

    for (final file in info.fileStats) {
      if (!_streamableExtensions.contains(
        p.extension(file.path).toLowerCase(),
      )) {
        continue;
      }
      if (selected == null || file.length > selected.length) {
        selected = file;
      }
    }

    return selected;
  }

  Future<File> _downloadTorrentFile(String url) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(dir.path, "${DateTime.now().millisecondsSinceEpoch}.torrent"),
    );

    final response = await _client.get(Uri.parse(url));
    await file.writeAsBytes(response.bodyBytes);

    return file;
  }

  @override
  String get id => "torrserver";

  @override
  String get name => "TorrServer";

  @override
  IconData get icon => Icons.extension;

  static const _owner = "YouROK";
  static const _repo = "TorrServer";
  static const _version = "MatriX.146.1";

  String get _versionKey => "${id}_version";
  String get _updateKey => "${id}_update";

  Future<Directory> get _directory async {
    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: "bridge/torrserver",
      useSystemPath: true,
      useCustomPath: false,
    );

    if (dir == null) {
      throw Exception("Failed to get TorrServer directory");
    }

    await dir.create(recursive: true);

    return dir;
  }

  String get _binaryName =>
      Platform.isWindows ? "torrserver.exe" : "torrserver";

  Future<File> get _binaryFile async =>
      File(p.join((await _directory).path, _binaryName));

  /// Path to the installed binary, or null if not installed. Pass this as
  /// `customBinaryPath` to [TorrServerControllerSubprocess.start].
  Future<String?> get binaryPath async {
    final file = await _binaryFile;
    if (!await file.exists()) return null;
    if (!await _matchesCpu(file)) {
      Logger.log(
        "TorrServer binary was built for another CPU, downloading the right one",
      );
      await file.delete();
      await install();
    }
    return await file.exists() ? file.path : null;
  }

  (int, int)? get _expectedElf {
    if (!Platform.isAndroid && !Platform.isLinux) return null;
    return switch (Abi.current()) {
      Abi.androidArm64 || Abi.linuxArm64 => (2, 0xB7),
      Abi.androidArm || Abi.linuxArm => (1, 0x28),
      Abi.androidX64 || Abi.linuxX64 => (2, 0x3E),
      Abi.androidIA32 || Abi.linuxIA32 => (1, 0x03),
      _ => null,
    };
  }

  Future<bool> _matchesCpu(File file) async {
    final expected = _expectedElf;
    if (expected == null) return true;
    try {
      final head = <int>[];
      await for (final chunk in file.openRead(0, 20)) {
        head.addAll(chunk);
      }
      if (head.length < 20) return false;
      final isElf =
          head[0] == 0x7F &&
          head[1] == 0x45 &&
          head[2] == 0x4C &&
          head[3] == 0x46;
      if (!isElf) return false;
      final littleEndian = head[5] == 1;
      final machine = littleEndian
          ? head[18] | (head[19] << 8)
          : (head[18] << 8) | head[19];
      return head[4] == expected.$1 && machine == expected.$2;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<bool> isInstalled() async {
    if (Platform.isIOS) return true;
    final file = await _binaryFile;
    return await file.exists() && await _matchesCpu(file);
  }

  /// YouROK/TorrServer release assets are plain binaries named
  /// `TorrServer-{os}-{arch}` (`.exe` on Windows) - no archive to extract,
  /// unlike the old `torrserver_flutter` fork this addon used to point at.
  String get _assetName {
    if (Platform.isWindows) {
      return "TorrServer-windows-amd64.exe";
    }
    if (Platform.isMacOS) {
      return "TorrServer-darwin-${_isArm ? "arm64" : "amd64"}";
    }
    if (Platform.isLinux) {
      return "TorrServer-linux-${_isArm ? "arm64" : "amd64"}";
    }
    if (Platform.isAndroid) {
      return "TorrServer-android-$_androidAbi";
    }
    throw UnsupportedError(
      "TorrServerAddon only downloads for Windows/macOS/Linux/Android; "
      "iOS embeds its xcframework instead.",
    );
  }

  bool get _isArm =>
      Platform.version.toLowerCase().contains("arm") ||
      Platform.version.toLowerCase().contains("aarch64");

  /// Maps the running ABI to YouROK/TorrServer's Android asset naming
  /// (`TorrServer-android-{arm64,amd64,arm7,386}`).
  String get _androidAbi {
    switch (Abi.current()) {
      case Abi.androidArm64:
        return "arm64";
      case Abi.androidArm:
        return "arm7";
      case Abi.androidX64:
        return "amd64";
      case Abi.androidIA32:
        return "386";
      default:
        throw UnsupportedError("Unsupported Android ABI: ${Abi.current()}");
    }
  }

  @override
  Future<void> install() async {
    if (downloading.value) return;

    downloading.value = true;
    progress.value = 0;

    try {
      await _download();

      installed.value = true;
      hasUpdate.value = false;
      setVal(_versionKey, _version);

      Logger.log("Installed TorrServer", show: true);
    } finally {
      downloading.value = false;
    }
  }

  @override
  Future<void> uninstall() async {
    await _controller?.stop();
    _controller = null;
    _activeHash = null;

    final dir = await _directory;

    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    installed.value = false;
    hasUpdate.value = false;

    setVal(_versionKey, "");
    setVal(_updateKey, false);
  }

  @override
  Future<bool> checkForUpdate() async {
    if (!await isInstalled()) return false;
    if (Platform.isIOS) return false;

    final local = getVal<String>(_versionKey, defaultValue: "") ?? "";
    final update = _version != local;

    setVal(_updateKey, update);
    hasUpdate.value = update;
    return update;
  }

  @override
  Future<void> update() async {
    if (!await checkForUpdate()) return;
    await uninstall();
    await install();
  }

  Future<void> _download() async {
    final url =
        "https://github.com/$_owner/$_repo/releases/download/$_version/$_assetName";

    final request = http.Request("GET", Uri.parse(url));
    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw Exception("Failed to download TorrServer (${response.statusCode})");
    }

    final binary = await _binaryFile;
    final sink = binary.openWrite();
    int received = 0;
    final total = response.contentLength ?? 0;

    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 60),
    )) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        progress.value = received / total;
      }
    }

    await sink.flush();
    await sink.close();

    if (!Platform.isWindows) {
      await Process.run("chmod", ["755", binary.path]);
    }

    progress.value = 1;
  }
}
