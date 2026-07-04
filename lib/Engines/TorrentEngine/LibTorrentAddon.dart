import 'dart:convert';
import 'dart:ffi';
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
import 'LibtorrentFlutter.dart';

class LibtorrentAddon extends Addon {
  final _client = MClient.init();
  LibtorrentAddon() {
    init();
  }

  Future<void> init() async {
    if (!(await isInstalled())) return;
    await LibtorrentFlutter.init(
      defaultSavePath: (await _directory).path,
      torrentLib: await open(),
    );
  }

  DynamicLibrary? _library;

  @override
  String get id => "libtorrent";

  @override
  String get name => "TorrentAddon";

  @override
  get icon => Icons.extension;

  static const _owner = "ayman708-UX";
  static const _repo = "libtorrent_flutter";

  String get _versionKey => "${id}_version";
  String get _updateKey => "${id}_update";

  Future<Directory> get _directory async {
    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: "bridge/libtorrent",
      useSystemPath: true,
      useCustomPath: false,
    );

    if (dir == null) {
      throw ("Failed to get libtorrent directory");
    }

    await dir.create(recursive: true);

    return dir;
  }

  String get _assetName {
    if (Platform.isWindows) {
      return "windows-native-lib-x64.zip";
    }

    if (Platform.isLinux) {
      return "linux-native-lib-x64.zip";
    }

    if (Platform.isMacOS) {
      return "macos-native-lib.zip";
    }

    if (Platform.isIOS) {
      return "ios-native-lib.zip";
    }

    if (Platform.isAndroid) {
      switch (Abi.current()) {
        case Abi.androidArm:
          return "android-native-lib-armeabi-v7a.zip";
        case Abi.androidArm64:
          return "android-native-lib-arm64-v8a.zip";
        case Abi.androidX64:
          return "android-native-lib-x86_64.zip";
        default:
          throw UnsupportedError("Unsupported Android ABI: ${Abi.current()}");
      }
    }

    throw UnsupportedError("Unsupported platform ${Platform.operatingSystem}");
  }

  String get _libraryName {
    if (Platform.isWindows) {
      return "libtorrent_flutter.dll";
    }

    if (Platform.isLinux || Platform.isAndroid) {
      return "liblibtorrent_flutter.so";
    }

    return "liblibtorrent_flutter.dylib";
  }

  Future<File?> get _libraryFile async {
    final dir = await _directory;

    final file = await _findLibrary(dir);

    return file;
  }

  @override
  Future<bool> isInstalled() async {
    return (await _libraryFile)?.exists() ?? false;
  }

  Future<DynamicLibrary?> open() async {
    if (!await isInstalled()) {
      return null;
    }

    return _library ??= DynamicLibrary.open((await _libraryFile)!.path);
  }

  Future<File?> _findLibrary(Directory dir) async {
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && p.basename(entity.path) == _libraryName) {
        return entity;
      }
    }
    return null;
  }

  @override
  Future<void> install() async {
    if (downloading.value) return;

    downloading.value = true;
    progress.value = 0;

    try {
      final release = await _latestRelease();

      await _download(release.$1, release.$2);

      installed.value = true;

      Logger.log("Installed libtorrent", show: true);
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

    _library = null;

    installed.value = false;

    setVal(_versionKey, "");
    setVal(_updateKey, false);
  }

  @override
  Future<bool> checkForUpdate() async {
    if (!await isInstalled()) {
      return false;
    }

    final release = await _latestRelease();

    final local = getVal<String>(_versionKey, defaultValue: "") ?? "";

    final update = release.$2 != local;

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

  Future<(String, String)> _latestRelease() async {
    final response = await _client.get(
      Uri.parse("https://api.github.com/repos/$_owner/$_repo/releases/latest"),
    );

    if (response.statusCode != 200) {
      throw Exception("Unable to fetch GitHub release");
    }

    final json = jsonDecode(response.body);

    final asset = (json["assets"] as List).firstWhere(
      (e) => e["name"] == _assetName,
      orElse: () => throw Exception("$_assetName not found"),
    );

    return (
      asset["browser_download_url"] as String,
      json["tag_name"] as String,
    );
  }

  Future<void> _download(String url, String version) async {
    final request = http.Request("GET", Uri.parse(url));

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw Exception("Download failed");
    }

    final dir = await _directory;

    final zip = File(p.join(dir.path, _assetName));

    final sink = zip.openWrite();

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

    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());

    await extractArchiveToDisk(archive, dir.path);

    await zip.delete();

    progress.value = 1;

    setVal(_versionKey, version);
    setVal(_updateKey, false);
  }
}
