import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;

import '../../Logger.dart';
import '../../NetworkClient.dart';
import '../../dartotsu_extension_bridge.dart';

class JavaRuntimeManager {
  static String? _cachedJavaPath;
  static String? _cachedJvmPath;
  static Future<String?>? _installFuture;
  static Future<Directory> get _runtimeDir async {
    final dir = await DartotsuExtensionBridge.context.getDirectory(
      subPath: 'bridge/jre',
      useSystemPath: true,
      useCustomPath: false,
    );

    if (dir == null) {
      throw Exception('Unable to get runtime directory');
    }

    await dir.create(recursive: true);
    return dir;
  }

  static Future<bool> isInstalled() async {
    return await getSystemJavaPath() != null || await getJavaPath() != null;
  }

  static Future<String?> getSystemJavaPath() async {
    try {
      final result = await Process.run('java', ['-version'], runInShell: true);

      if (result.exitCode == 0) {
        Logger.log('System Java found');
        return 'java';
      }
    } catch (_) {}

    return null;
  }

  static Future<String?> getJvmPath() async {
    await ensureInstalled();

    if (_cachedJvmPath != null) {
      return _cachedJvmPath;
    }

    final javaPath = await getJavaPath();

    if (javaPath == null || javaPath == 'java') {
      return null;
    }

    final javaFile = File(javaPath);
    final javaHome = javaFile.parent.parent;

    if (Platform.isWindows) {
      final jvm = File('${javaHome.path}/bin/server/jvm.dll');

      if (await jvm.exists()) {
        return _cachedJvmPath = jvm.path;
      }
    } else if (Platform.isMacOS) {
      final jvm = File('${javaHome.path}/lib/server/libjvm.dylib');

      if (await jvm.exists()) {
        return _cachedJvmPath = jvm.path;
      }
    } else {
      final jvm = File('${javaHome.path}/lib/server/libjvm.so');

      if (await jvm.exists()) {
        return _cachedJvmPath = jvm.path;
      }
    }

    return null;
  }

  static Future<String?> ensureInstalled() {
    return _installFuture ??= _ensureInstalledImpl().whenComplete(() {
      _installFuture = null;
    });
  }

  static Future<String?> _ensureInstalledImpl() async {
    final systemJava = await getSystemJavaPath();

    if (systemJava != null) {
      return systemJava;
    }

    final bundledJava = await getJavaPath();

    if (bundledJava != null) {
      return bundledJava;
    }

    Logger.log('Installing Java Runtime...', show: true);

    final archive = await _download();

    try {
      await _extract(archive);
    } finally {
      if (await archive.exists()) {
        await archive.delete();
      }
    }

    final java = await getJavaPath();

    if (java == null) {
      throw Exception('Failed to install Java runtime');
    }

    Logger.log('Java Runtime installed', show: true);

    return java;
  }

  static Future<String?> getJavaPath() async {
    if (_cachedJavaPath != null) {
      return _cachedJavaPath;
    }

    final root = await _runtimeDir;

    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;

      final name = entity.uri.pathSegments.last.toLowerCase();

      if (Platform.isWindows && name == 'java.exe') {
        return _cachedJavaPath = entity.path;
      }

      if (!Platform.isWindows && name == 'java') {
        return _cachedJavaPath = entity.path;
      }
    }

    return null;
  }

  static Future<File> _download() async {
    final root = await _runtimeDir;

    final extension = _jreUrl.endsWith('.zip') ? 'zip' : 'tar.gz';

    final file = File('${root.path}/jre.$extension');

    final client = MClient.init();

    try {
      final request = http.Request('GET', Uri.parse(_jreUrl));

      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Download failed (${response.statusCode})');
      }

      final sink = file.openWrite();

      final total = response.contentLength ?? 0;

      int downloaded = 0;
      int lastLogged = DateTime.now().millisecondsSinceEpoch;

      await for (final chunk in response.stream) {
        downloaded += chunk.length;
        sink.add(chunk);

        final now = DateTime.now().millisecondsSinceEpoch;

        if (now - lastLogged >= 1000) {
          lastLogged = now;

          if (total > 0) {
            final percent = (downloaded / total * 100).toStringAsFixed(1);

            Logger.log(
              'Downloading Java Runtime: '
              '$percent% '
              '(${_formatSize(downloaded)}/${_formatSize(total)})',
              show: true,
            );
          } else {
            Logger.log(
              'Downloading Java Runtime: '
              '${_formatSize(downloaded)}',
              show: true,
            );
          }
        }
      }

      await sink.flush();
      await sink.close();

      return file;
    } finally {
      client.close();
    }
  }

  static String _formatSize(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }

    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(2)} MB';
    }

    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(2)} KB';
    }

    return '$bytes B';
  }

  static Future<void> _extract(File archiveFile) async {
    final root = await _runtimeDir;

    final bytes = await archiveFile.readAsBytes();

    Archive archive;

    if (archiveFile.path.endsWith('.zip')) {
      archive = ZipDecoder().decodeBytes(bytes);
    } else {
      final tarBytes = const GZipDecoder().decodeBytes(bytes);
      archive = TarDecoder().decodeBytes(tarBytes);
    }

    await extractArchiveToDisk(archive, root.path);

    if (!Platform.isWindows) {
      await _fixPermissions(root);
    }
  }

  static Future<void> _fixPermissions(Directory root) async {
    try {
      final java = await getJavaPath();

      if (java != null) {
        await Process.run('chmod', ['+x', java]);
      }
    } catch (_) {}
  }

  static String get _jreUrl {
    if (Platform.isWindows) {
      return 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_x64_windows_hotspot_17.0.12_7.zip';
    }

    if (Platform.isMacOS) {
      if (_arch == 'arm64') {
        return 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_aarch64_mac_hotspot_17.0.12_7.tar.gz';
      }

      return 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_x64_mac_hotspot_17.0.12_7.tar.gz';
    }

    if (_arch == 'arm64') {
      return 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_aarch64_linux_hotspot_17.0.12_7.tar.gz';
    }

    return 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_x64_linux_hotspot_17.0.12_7.tar.gz';
  }

  static String get _arch {
    switch (Abi.current()) {
      case Abi.linuxArm64:
      case Abi.macosArm64:
      case Abi.windowsArm64:
        return 'arm64';

      default:
        return 'x64';
    }
  }

  static Future<void> uninstall() async {
    final dir = await _runtimeDir;

    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    _cachedJavaPath = null;
    _cachedJvmPath = null;
    _installFuture = null;
  }
}
