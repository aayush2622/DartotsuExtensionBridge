import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../ExtensionBridge.dart';
import '../../Extensions/Addon.dart';
import '../../Logger.dart';
import '../../Network/MClient.dart';
import '../../Settings/KvStore.dart';

class MpvBundle {
  final String url;
  final String sha256;
  final bool sevenZip;
  final String root;
  final String library;

  const MpvBundle(
    this.url,
    this.sha256,
    this.library, {
    this.root = '',
    this.sevenZip = false,
  });

  String get version => sha256.substring(0, 16);
}

class MpvCancelled implements Exception {
  const MpvCancelled();

  @override
  String toString() => 'cancelled';
}

class MpvAddon extends Addon {
  static const _android =
      'https://github.com/Predidit/libmpv-android-video-build/releases/download/v1.3.1';
  static const _windows =
      'https://github.com/Predidit/libmpv-win32-video-cmake/releases/download/202611120335';
  static const _linux =
      'https://github.com/Predidit/libmpv-linux-build/releases/download/20260810';

  static const _bundles = <Abi, MpvBundle>{
    Abi.androidArm64: MpvBundle(
      '$_android/default-arm64-v8a.jar',
      '3bbceecd7616d5730e19865342a020834f00bdf77c25900e97c91a6e3e8141f8',
      'libmpv.so',
      root: 'lib/arm64-v8a',
    ),
    Abi.androidArm: MpvBundle(
      '$_android/default-armeabi-v7a.jar',
      '96c37141ef20d1c73da01887f8ad6244aa7fccb44e805457d3eb15d2d71fde20',
      'libmpv.so',
      root: 'lib/armeabi-v7a',
    ),
    Abi.androidX64: MpvBundle(
      '$_android/default-x86_64.jar',
      'f01e9f1890091f4dd856cd37247e442d151b7815a86306581a1e9317ec566136',
      'libmpv.so',
      root: 'lib/x86_64',
    ),
    Abi.androidIA32: MpvBundle(
      '$_android/default-x86.jar',
      '29919fb6d0e4cd3855ef4c951f1d1e7784889e8715bad3007e718f18b425d4bd',
      'libmpv.so',
      root: 'lib/x86',
    ),
    Abi.windowsArm64: MpvBundle(
      '$_windows/mpv-dev-aarch64-20261112-git-bcde6b9.zip',
      '9e0733b8c31add5b489364d209729c50ee569827573ef2c1bb1c6f6caa783810',
      'libmpv-2.dll',
    ),
    Abi.windowsX64: MpvBundle(
      '$_windows/mpv-dev-x86_64-20261112-git-bcde6b9.7z',
      '297de0494d7a8687ce42acda1e3a63b0ce86c099f09e0627020558c44aae323b',
      'libmpv-2.dll',
      sevenZip: true,
    ),
    Abi.linuxX64: MpvBundle(
      '$_linux/libmpv_x86_64.zip',
      '45922100e5240bf69a72fa2ae140d5b54e1ed03993a8a3746dc798e3ae8ad6e4',
      'libmpv.so.2',
    ),
    Abi.linuxArm64: MpvBundle(
      '$_linux/libmpv_aarch64.zip',
      'da0609556e2864dbe828102972edea96173a4be1ad1427a7493942dccb039b9f',
      'libmpv.so.2',
    ),
  };

  final _client = MClient.download();

  final received = 0.obs;
  final total = 0.obs;
  final error = RxnString();

  Future<void>? _job;
  bool _cancelled = false;

  /// macOS and iOS keep libmpv inside the app (an XCFramework the Swift
  /// plugin links against), so there is nothing to download there.
  static bool get bundled => Platform.isIOS || Platform.isMacOS;

  @visibleForTesting
  static Map<Abi, MpvBundle> get catalog => _bundles;

  static MpvBundle? get _bundle => _bundles[Abi.current()];

  /// Whether this platform fetches libmpv at runtime (every one but iOS and macOS).
  static bool get downloadable => !bundled && _bundle != null;

  @override
  String get id => 'mpv';

  @override
  String get name => 'Player';

  @override
  IconData get icon => Icons.play_circle_rounded;

  String get _versionKey => '${id}_version';

  static const _forcedPath = 'LIBMPV_LIBRARY_PATH';

  String? get _override {
    final value = Platform.environment[_forcedPath];
    return value == null || value.isEmpty ? null : value;
  }

  Future<Directory> get _directory async {
    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/mpv',
      useSystemPath: true,
      useCustomPath: false,
    );
    if (dir == null) throw Exception('Failed to get the player directory');
    await dir.create(recursive: true);
    return dir;
  }

  Future<File?> _installedFile() async {
    final bundle = _bundle;
    final stored = getVal<String>(_versionKey, defaultValue: '') ?? '';
    if (bundle == null || stored.isEmpty) return null;
    final file = File(p.join((await _directory).path, stored, bundle.library));
    return await file.exists() ? file : null;
  }

  /// Where media_kit should load libmpv from: the path in `LIBMPV_LIBRARY_PATH`
  /// when set, the downloaded file, or null when the player must be
  /// downloaded first (or ships inside the app, see [bundled]).
  Future<String?> get libraryPath async {
    final forced = _override;
    if (forced != null) return forced;
    if (bundled) return null;
    return (await _installedFile())?.path;
  }

  /// True when the app can initialise the player right now.
  Future<bool> get ready async => bundled || (await libraryPath) != null;

  @override
  Future<bool> isInstalled() async {
    if (bundled || _override != null) return true;
    return (await _installedFile()) != null;
  }

  @override
  Future<void> install() {
    if (!downloadable) return Future.value();
    return _job ??= _install().whenComplete(() => _job = null);
  }

  void cancel() => _cancelled = true;

  Future<void> _install() async {
    final bundle = _bundle!;
    _cancelled = false;
    downloading.value = true;
    progress.value = 0;
    received.value = 0;
    total.value = 0;
    error.value = null;
    final dir = await _directory;
    final partial = File(p.join(dir.path, 'download.part'));
    final target = Directory(p.join(dir.path, bundle.version));
    try {
      await _download(bundle, partial);
      progress.value = 0.95;
      await _verify(partial, bundle);
      if (await target.exists()) await target.delete(recursive: true);
      await target.create(recursive: true);
      final file = await _extract(bundle, partial, target);
      if (!Platform.isWindows) await Process.run('chmod', ['444', file.path]);
      setVal(_versionKey, bundle.version);
      await _prune(dir, keep: bundle.version);
      installed.value = true;
      hasUpdate.value = false;
      progress.value = 1;
      Logger.log('Installed the player');
    } catch (e) {
      if (await target.exists()) await target.delete(recursive: true);
      if (e is! MpvCancelled) {
        error.value = '$e';
        Logger.log('Installing the player failed: $e');
      }
      rethrow;
    } finally {
      if (_cancelled && await partial.exists()) await partial.delete();
      downloading.value = false;
    }
  }

  Future<void> _download(MpvBundle bundle, File partial) async {
    var attempt = 0;
    while (true) {
      try {
        await _fetch(bundle, partial);
        return;
      } on MpvCancelled {
        rethrow;
      } catch (e) {
        attempt++;
        Logger.log('Player download attempt $attempt failed: $e');
        if (attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt * 2));
        if (_cancelled) throw const MpvCancelled();
      }
    }
  }

  Future<void> _fetch(MpvBundle bundle, File partial) async {
    final have = await partial.exists() ? await partial.length() : 0;
    final request = http.Request('GET', Uri.parse(bundle.url));
    if (have > 0) request.headers['Range'] = 'bytes=$have-';
    final response = await _client.send(request);
    final resumed = response.statusCode == 206 && have > 0;
    if (response.statusCode != 200 && !resumed) {
      if (response.statusCode == 416 && have > 0) {
        await partial.delete();
      }
      throw Exception('Failed to download the player (${response.statusCode})');
    }
    final start = resumed ? have : 0;
    final length = response.contentLength;
    total.value = length == null ? 0 : start + length;
    final sink = partial.openWrite(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    var done = start;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (_cancelled) throw const MpvCancelled();
        sink.add(chunk);
        done += chunk.length;
        received.value = done;
        if (total.value > 0) progress.value = done / total.value * 0.95;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<void> _verify(File file, MpvBundle bundle) async {
    final digest = await sha256.bind(file.openRead()).first;
    if ('$digest' != bundle.sha256) {
      await file.delete();
      throw Exception('The downloaded player is damaged, try again');
    }
  }

  Future<File> _extract(MpvBundle bundle, File archive, Directory to) async {
    final out = File(p.join(to.path, bundle.library));
    if (bundle.sevenZip) {
      final scratch = Directory(p.join(to.path, '.unpack'));
      await scratch.create(recursive: true);
      try {
        final result = await Process.run('tar', [
          '-xf',
          archive.path,
          '-C',
          scratch.path,
        ]);
        if (result.exitCode != 0) {
          throw Exception('Could not unpack the player: ${result.stderr}');
        }
        await for (final entity in scratch.list(recursive: true)) {
          if (entity is File && p.basename(entity.path) == bundle.library) {
            await entity.copy(out.path);
            break;
          }
        }
      } finally {
        await scratch.delete(recursive: true);
      }
    } else {
      final input = InputFileStream(archive.path);
      try {
        final zip = ZipDecoder().decodeStream(input);
        final wanted = bundle.root.isEmpty
            ? bundle.library
            : '${bundle.root}/${bundle.library}';
        for (final entry in zip) {
          if (!entry.isFile) continue;
          final match = bundle.root.isEmpty
              ? p.basename(entry.name) == bundle.library
              : entry.name == wanted;
          if (!match) continue;
          final sink = OutputFileStream(out.path);
          try {
            entry.writeContent(sink);
          } finally {
            await sink.close();
          }
          break;
        }
      } finally {
        await input.close();
      }
    }
    if (!await out.exists() || await out.length() < 1024 * 1024) {
      throw Exception('The player archive had no ${bundle.library}');
    }
    return out;
  }

  Future<void> _prune(Directory dir, {required String keep}) async {
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (name == keep) continue;
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  @override
  Future<void> uninstall() async {
    if (bundled) return;
    cancel();
    final dir = await _directory;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      Logger.log('Could not remove the player: $e');
    }
    installed.value = _override != null;
    hasUpdate.value = false;
    setVal(_versionKey, '');
  }

  @override
  Future<bool> checkForUpdate() async {
    final bundle = _bundle;
    if (bundled || bundle == null || !installed.value) return false;
    final stored = getVal<String>(_versionKey, defaultValue: '') ?? '';
    final newer = stored.isNotEmpty && stored != bundle.version;
    hasUpdate.value = newer;
    return newer;
  }

  @override
  Future<void> update() => install();
}
