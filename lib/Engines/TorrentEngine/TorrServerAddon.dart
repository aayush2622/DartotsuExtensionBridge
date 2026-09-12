import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../Extensions/Addon.dart';
import '../../Logger.dart';
import '../../NetworkClient.dart';
import '../../Settings/KvStore.dart';
import '../../dartotsu_extension_bridge.dart';

/// Downloads and installs the TorrServer subprocess binary for Windows,
/// Linux, and macOS at app runtime.
///
/// Android's binary is baked into the APK at build time instead (see
/// `android/build.gradle.kts`) — a runtime-downloaded file generally can't be
/// exec'd on modern Android (W^X / SELinux `noexec` on writable app-data
/// partitions) — so [isInstalled] is unconditionally `true` there. iOS embeds
/// `TorrServerKit.xcframework` at build time too, so it's not installable
/// through this addon either; use [TorrServerControllerIos] directly there.
class TorrServerAddon extends Addon {
  final _client = MClient.init();

  TorrServerAddon();

  @override
  String get id => "torrserver";

  @override
  String get name => "TorrServer";

  @override
  IconData get icon => Icons.extension;

  static const _owner = "ayman708-UX";
  static const _repo = "torrserver_flutter";
  static const _version = "v0.0.6";

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

  String get _binaryName => Platform.isWindows ? "torrserver.exe" : "torrserver";

  Future<File> get _binaryFile async =>
      File(p.join((await _directory).path, _binaryName));

  /// Path to the installed binary, or null if not installed. Pass this as
  /// `customBinaryPath` to [TorrServerControllerSubprocess.start].
  Future<String?> get binaryPath async {
    final file = await _binaryFile;
    return await file.exists() ? file.path : null;
  }

  @override
  Future<bool> isInstalled() async {
    if (Platform.isAndroid || Platform.isIOS) return true;
    return (await _binaryFile).exists();
  }

  String get _archiveName {
    if (Platform.isWindows) {
      return "torrserver-windows-amd64.zip";
    }
    if (Platform.isMacOS) {
      final arch = _isArm ? "arm64" : "amd64";
      return "torrserver-darwin-$arch.tar.gz";
    }
    if (Platform.isLinux) {
      final arch = _isArm ? "arm64" : "amd64";
      return "torrserver-linux-$arch.tar.gz";
    }
    throw UnsupportedError(
      "TorrServerAddon only downloads for Windows/macOS/Linux; "
      "Android bundles its binary at build time, iOS embeds its xcframework.",
    );
  }

  String get _entryName {
    if (Platform.isWindows) return "torrserver-windows-amd64.exe";
    if (Platform.isMacOS) return "torrserver-darwin-${_isArm ? "arm64" : "amd64"}";
    return "torrserver-linux-${_isArm ? "arm64" : "amd64"}";
  }

  bool get _isArm =>
      Platform.version.toLowerCase().contains("arm") ||
      Platform.version.toLowerCase().contains("aarch64");

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
    if (Platform.isAndroid || Platform.isIOS) return false;

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
        "https://github.com/$_owner/$_repo/releases/download/$_version/$_archiveName";

    final request = http.Request("GET", Uri.parse(url));
    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw Exception("Failed to download TorrServer (${response.statusCode})");
    }

    final dir = await _directory;
    final archiveFile = File(p.join(dir.path, _archiveName));

    final sink = archiveFile.openWrite();
    int received = 0;
    final total = response.contentLength ?? 0;

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        progress.value = received / total;
      }
    }

    await sink.flush();
    await sink.close();

    final bytes = await archiveFile.readAsBytes();
    final archive = _archiveName.endsWith(".zip")
        ? ZipDecoder().decodeBytes(bytes)
        : TarDecoder().decodeBytes(const GZipDecoder().decodeBytes(bytes));

    final entry = archive.files.firstWhere(
      (f) => f.isFile && p.basename(f.name) == _entryName,
      orElse: () => throw Exception("$_entryName not found in $_archiveName"),
    );

    final binary = await _binaryFile;
    await binary.writeAsBytes(entry.content as List<int>);
    await archiveFile.delete();

    if (!Platform.isWindows) {
      await Process.run("chmod", ["755", binary.path]);
    }

    progress.value = 1;
  }
}
