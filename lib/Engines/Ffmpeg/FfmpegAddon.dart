import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../ExtensionBridge.dart';
import '../../Extensions/Addon.dart';
import '../../Logger.dart';
import '../../Network/MClient.dart';
import '../../Settings/KvStore.dart';

class FfmpegCancel {
  Process? _process;
  bool running = false;
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    _process?.kill();
    if (running) FfmpegAddon._cancelEmbedded();
  }
}

class FfmpegFailure implements Exception {
  final int code;
  final String output;

  const FfmpegFailure(this.code, this.output);

  @override
  String toString() => 'ffmpeg exited with $code: $output';
}

class FfmpegAddon extends Addon {
  final _client = MClient.download();

  FfmpegAddon() {
    if (Platform.isIOS && _embedded) installed.value = true;
  }

  static final bool _embedded = _probeEmbedded();

  static bool _probeEmbedded() {
    if (!Platform.isIOS) return false;
    try {
      return DynamicLibrary.process().providesSymbol('dartotsu_ffmpeg_run');
    } catch (_) {
      return false;
    }
  }

  static void _cancelEmbedded() {
    try {
      DynamicLibrary.process().lookupFunction<Void Function(), void Function()>(
        'dartotsu_ffmpeg_cancel',
      )();
    } catch (_) {}
  }

  static int _runEmbedded(List<String> argv) {
    final lib = DynamicLibrary.process();
    final run = lib
        .lookupFunction<
          Int32 Function(Int32, Pointer<Pointer<Utf8>>),
          int Function(int, Pointer<Pointer<Utf8>>)
        >('dartotsu_ffmpeg_run');
    final args = ['ffmpeg', ...argv];
    final vector = calloc<Pointer<Utf8>>(args.length + 1);
    for (var i = 0; i < args.length; i++) {
      vector[i] = args[i].toNativeUtf8();
    }
    try {
      return run(args.length, vector);
    } finally {
      for (var i = 0; i < args.length; i++) {
        calloc.free(vector[i]);
      }
      calloc.free(vector);
    }
  }

  @override
  String get id => 'ffmpeg';

  @override
  String get name => 'FFmpeg';

  @override
  IconData get icon => Icons.movie_filter_rounded;

  static const _version = 'mini-7.1.1';
  static const _fullVersion = 'btbn-latest';
  static const _btbn =
      'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest';
  static const _release =
      'https://raw.githubusercontent.com/aayush2622/DartotsuExtensionBridge/master/ffmpeg';

  String get _versionKey => '${id}_version';

  static const _linker = '/system/bin/linker64';

  static (String, List<String>) launch(String binary, List<String> args) =>
      Platform.isAndroid ? (_linker, [binary, ...args]) : (binary, args);

  bool get supported {
    if (Platform.isIOS) return _embedded;
    if (Platform.isAndroid) return Abi.current() == Abi.androidArm64;
    return true;
  }

  Future<Directory> get _directory async {
    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/ffmpeg',
      useSystemPath: true,
      useCustomPath: false,
    );
    if (dir == null) throw Exception('Failed to get the FFmpeg directory');
    await dir.create(recursive: true);
    return dir;
  }

  String get _binaryName => Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';

  Future<File> get _binaryFile async =>
      File(p.join((await _directory).path, _binaryName));

  Future<String?> get binaryPath async {
    final file = await _binaryFile;
    return await file.exists() ? file.path : null;
  }

  String get _assetUrl {
    final abi = Abi.current();
    final String target;
    if (Platform.isWindows) {
      target = abi == Abi.windowsArm64
          ? 'windows-arm64.exe'
          : 'windows-x64.exe';
    } else if (Platform.isMacOS) {
      target = abi == Abi.macosArm64 ? 'macos-arm64' : 'macos-x64';
    } else if (Platform.isAndroid) {
      target = 'android-arm64';
    } else if (Platform.isLinux) {
      target = abi == Abi.linuxArm64 ? 'linux-arm64' : 'linux-x64';
    } else {
      throw UnsupportedError('FFmpeg is not available on this platform');
    }
    return '$_release/ffmpeg-$target';
  }

  ({String url, bool zip}) get _fullAsset {
    final abi = Abi.current();
    if (Platform.isWindows) {
      final arm = abi == Abi.windowsArm64;
      return (
        url: '$_btbn/ffmpeg-master-latest-win${arm ? 'arm64' : '64'}-gpl.zip',
        zip: true,
      );
    }
    if (Platform.isMacOS) {
      return (url: 'https://evermeet.cx/ffmpeg/getrelease/zip', zip: true);
    }
    final arm = Platform.isAndroid || abi == Abi.linuxArm64;
    return (
      url:
          '$_btbn/ffmpeg-master-latest-linux${arm ? 'arm64' : '64'}-gpl.tar.xz',
      zip: false,
    );
  }

  @override
  Future<bool> isInstalled() async {
    if (Platform.isIOS) return _embedded;
    if (!supported) return false;
    return (await _binaryFile).exists();
  }

  @override
  Future<void> install() async {
    if (Platform.isIOS) return;
    if (downloading.value) return;
    if (!supported) {
      throw UnsupportedError('FFmpeg is not available on this platform');
    }
    downloading.value = true;
    progress.value = 0;
    final binary = await _binaryFile;
    final partial = File('${binary.path}.part');
    var version = _version;
    try {
      try {
        await _download(_assetUrl, partial);
        progress.value = 0.95;
        if (await binary.exists()) await binary.delete();
        await partial.rename(binary.path);
        if (!Platform.isWindows) {
          await Process.run('chmod', ['755', binary.path]);
        }
        final (probeExe, probeArgs) = launch(binary.path, ['-version']);
        final probe = await Process.run(probeExe, probeArgs);
        if (probe.exitCode != 0) throw Exception('it does not run here');
      } catch (e) {
        if (await binary.exists()) await binary.delete();
        Logger.log('Small FFmpeg unavailable ($e), using the full build');
        version = _fullVersion;
        progress.value = 0;
        if (await partial.exists()) await partial.delete();
        await _installFull(await _directory);
      }
      if (!Platform.isWindows) {
        await Process.run('chmod', ['755', binary.path]);
      }
      final (checkExe, checkArgs) = launch(binary.path, ['-version']);
      final check = await Process.run(checkExe, checkArgs);
      if (check.exitCode != 0) {
        await binary.delete();
        throw Exception('The downloaded FFmpeg does not run on this device');
      }
      installed.value = true;
      hasUpdate.value = false;
      setVal(_versionKey, version);
      progress.value = 1;
      Logger.log('Installed FFmpeg', show: true);
    } finally {
      if (await partial.exists()) await partial.delete();
      downloading.value = false;
    }
  }

  Future<void> _installFull(Directory dir) async {
    final asset = _fullAsset;
    final archive = File(
      p.join(dir.path, asset.zip ? 'ffmpeg.zip' : 'ffmpeg.tar.xz'),
    );
    try {
      await _download(asset.url, archive);
      progress.value = 0.95;
      if (asset.zip) {
        await _extractZip(archive, dir);
      } else {
        await _extractTar(archive, dir);
      }
      if (!await (await _binaryFile).exists()) {
        throw Exception('The FFmpeg archive had no ffmpeg binary');
      }
    } finally {
      if (await archive.exists()) await archive.delete();
    }
  }

  Future<void> _extractZip(File archive, Directory dir) async {
    final input = InputFileStream(archive.path);
    try {
      final zip = ZipDecoder().decodeStream(input);
      for (final entry in zip) {
        if (!entry.isFile) continue;
        if (p.basename(entry.name) != _binaryName) continue;
        final out = OutputFileStream(p.join(dir.path, _binaryName));
        try {
          entry.writeContent(out);
        } finally {
          await out.close();
        }
        return;
      }
    } finally {
      await input.close();
    }
  }

  Future<void> _extractTar(File archive, Directory dir) async {
    final result = await Process.run('tar', [
      '-xJf',
      archive.path,
      '-C',
      dir.path,
      '--wildcards',
      '--strip-components=2',
      '*/bin/ffmpeg',
    ]);
    if (result.exitCode != 0) {
      throw Exception('Could not unpack FFmpeg: ${result.stderr}');
    }
  }

  Future<void> _download(String url, File target) async {
    final response = await _client.send(http.Request('GET', Uri.parse(url)));
    if (response.statusCode != 200) {
      throw Exception('Failed to download FFmpeg (${response.statusCode})');
    }
    final sink = target.openWrite();
    var received = 0;
    final total = response.contentLength ?? 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) progress.value = received / total * 0.95;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> uninstall() async {
    if (Platform.isIOS) return;
    final dir = await _directory;
    if (await dir.exists()) await dir.delete(recursive: true);
    installed.value = false;
    hasUpdate.value = false;
    setVal(_versionKey, '');
  }

  @override
  Future<bool> checkForUpdate() async => false;

  @override
  Future<void> update() async {}

  Future<void> run(
    List<String> args, {
    FfmpegCancel? cancel,
    void Function(String line)? onOutput,
  }) async {
    if (Platform.isIOS) return _runEmbeddedAsync(args, cancel);
    final binary = await binaryPath;
    if (binary == null) throw StateError('FFmpeg is not installed');
    final (exe, exeArgs) = launch(binary, [
      '-hide_banner',
      '-nostdin',
      '-y',
      ...args,
    ]);
    final process = await Process.start(exe, exeArgs);
    cancel?._process = process;
    if (cancel?.cancelled ?? false) process.kill();
    final tail = <String>[];
    void listen(Stream<List<int>> stream) {
      stream.transform(utf8.decoder).transform(const LineSplitter()).listen((
        line,
      ) {
        onOutput?.call(line);
        tail.add(line);
        if (tail.length > 12) tail.removeAt(0);
      });
    }

    listen(process.stdout);
    listen(process.stderr);
    final code = await process.exitCode;
    if (code != 0) throw FfmpegFailure(code, tail.join('\n'));
  }

  Future<void> _runEmbeddedAsync(
    List<String> args,
    FfmpegCancel? cancel,
  ) async {
    if (cancel?.cancelled ?? false) {
      throw const FfmpegFailure(255, 'cancelled');
    }
    cancel?.running = true;
    final full = ['-hide_banner', '-nostdin', '-y', ...args];
    try {
      final code = await Isolate.run(() => _runEmbedded(full));
      if (code != 0) throw FfmpegFailure(code, '');
    } finally {
      cancel?.running = false;
    }
  }

  Future<void> remuxPlaylist({
    required String playlist,
    required String output,
    FfmpegCancel? cancel,
  }) => run([
    '-allowed_extensions',
    'ALL',
    '-protocol_whitelist',
    'file,crypto,data',
    '-i',
    playlist,
    '-c',
    'copy',
    '-bsf:a',
    'aac_adtstoasc',
    '-movflags',
    '+faststart',
    output,
  ], cancel: cancel);
}
