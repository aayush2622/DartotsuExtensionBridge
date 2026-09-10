import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../Logger.dart';
import '../../dartotsu_extension_bridge.dart';
import 'PackagedSource.dart';
import 'TachiyomiRepo.dart';

/// `installSource` / `updateSource` / `uninstallSource` for the desktop
/// (JVM-sidecar) Tachiyomi backends — Aniyomi, IReader and Tsundoku.
///
/// All three were byte-identical bar the `bridge/<name>` data directory and the
/// concrete `Source` subtype; both are abstracted behind [jniDataDir] and
/// [PackagedSource]. The package file is downloaded into
/// `bridge/<jniDataDir>/extensions/<type>/` and the JVM side picks it up from
/// there on the next `getInstalled…` scan, so there's nothing else to call.
mixin TachiyomiJniDesktopExtension on Extension {
  /// HTTP client for the package download. Aniyomi/Tsundoku desktop already
  /// expose this for [TachiyomiRepoBackend]; IReader desktop supplies its own.
  http.Client get repoClient;

  /// Directory segment under `bridge/` that this backend keeps its extensions
  /// in — `'aniyomi'`, `'ireader'`, `'tsundoku'`.
  String get jniDataDir;

  Future<Directory?> _extensionsDir(ItemType type) =>
      DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/$jniDataDir/extensions/${type.toString()}',
        useSystemPath: false,
        useCustomPath: true,
      );

  @override
  Future<void> installSource(Source source) async {
    final s = source as PackagedSource;
    final type = source.itemType!;

    final downloadUrl = s.apkUrl;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw Exception("APK URL missing");
    }

    final fileName =
        s.apkName ?? s.pkgName ?? p.basename(Uri.parse(downloadUrl).path);
    if (fileName.isEmpty) {
      throw Exception("Can't determine a file name for ${s.name}");
    }

    final dir = await _extensionsDir(type);
    final file = File(p.join(dir!.path, fileName));

    // Capture the path of the version currently on disk (if any) before we
    // overwrite the field, so a rename between versions doesn't orphan a jar.
    final oldApkPath = s.apkPath;

    await downloadPackageFile(repoClient, downloadUrl, file.path);
    s.apkPath = file.path;

    if (oldApkPath != null && oldApkPath != file.path) {
      final oldFile = File(oldApkPath);
      if (await oldFile.exists()) {
        await oldFile.delete();
        Logger.log('Deleted old extension: ${oldFile.path}');
      }
    }

    final avail = state(type).available;
    avail.value = avail.value.where((e) => e.id != s.id).toList();
    await fetchInstalledExtensions(type);
    detectUpdates(state(type).rawAvailable.value, type);
  }

  @override
  Future<void> updateSource(Source source) => installSource(source);

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as PackagedSource;
    final type = source.itemType!;

    final apkFileName = s.apkPath != null
        ? p.basename(s.apkPath!)
        : (s.apkName ?? '${s.pkgName ?? s.id}.jar');

    final baseDir = await _extensionsDir(type);
    final file = File(p.join(baseDir!.path, apkFileName));

    if (await file.exists()) {
      await file.delete();
      Logger.log('Deleted private extension: ${s.name}');
    } else {
      Logger.log('Private extension file not found: ${s.name}');
    }

    final raw = state(type).rawAvailable.value;
    final installedIds = state(type).installed.value.map((e) => e.id).toSet();
    state(type).available.value = List.unmodifiable(
      raw.where((e) => !installedIds.contains(e.id)),
    );
    await fetchInstalledExtensions(type);
    detectUpdates(raw, type);
  }
}
