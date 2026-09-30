import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../Engines/JavaEngine/Bridge/JniBridge.dart';
import '../../Logger.dart';
import '../../dartotsu_extension_bridge.dart';
import 'PackagedSource.dart';
import 'TachiyomiRepo.dart';

mixin TachiyomiJniDesktopExtension on Extension {
  http.Client get repoClient;

  String get jniDataDir;

  JavaBridge get jni;

  Future<Directory?> _extensionsDir(ItemType type) =>
      DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/$jniDataDir/extensions/${type.toString()}',
        useSystemPath: false,
        useCustomPath: true,
      );

  Future<List<T>> loadInstalledJniSources<T extends PackagedSource>(
    String jniMethod,
    ItemType type,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final dir = await _extensionsDir(type);

      final result = await jni.call<List<Map<String, dynamic>>>(jniMethod, {
        "path": dir!.path,
      });

      final sources = result.map(fromJson).where((s) => s.itemType == type);

      final deduped = _dedupeById(sources);
      await _pruneObsoletePackageFiles(dir, deduped);
      return deduped;
    } catch (e, s) {
      Logger.log("Desktop loadInstalled error: $e\n$s");
      return [];
    }
  }

  Future<void> _pruneObsoletePackageFiles(
    Directory dir,
    List<PackagedSource> installed,
  ) async {
    final keep = installed
        .map((s) => s.apkPath)
        .whereType<String>()
        .map(p.basename)
        .toSet();

    if (!await dir.exists()) return;

    await for (final entry in dir.list()) {
      if (entry is! File || p.extension(entry.path) != '.apk') continue;
      if (keep.contains(p.basename(entry.path))) continue;

      try {
        await entry.delete();
        Logger.log('Deleted obsolete extension file: ${entry.path}');
      } catch (e) {
        Logger.log(
          'Failed to delete obsolete extension file ${entry.path}: $e',
        );
      }
    }
  }

  List<T> _dedupeById<T extends PackagedSource>(Iterable<T> sources) {
    final byId = <String, T>{};

    for (final source in sources) {
      final id = source.id;
      if (id == null || id.isEmpty || id == 'null') {
        Logger.log('Dropping installed source with invalid id: ${source.name}');
        continue;
      }

      final existing = byId[id];
      if (existing == null ||
          compareVersions(source.version ?? '', existing.version ?? '') > 0) {
        if (existing != null) {
          Logger.log(
            'Dropping duplicate installed source id=$id '
            '(kept version ${source.version}, dropped ${existing.version})',
          );
        }
        byId[id] = source;
      }
    }

    return byId.values.toList(growable: false);
  }

  @override
  Stream<double> installSource(Source source) {
    return progressStream((report) async {
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

      final oldApkPath = s.apkPath;

      final progressId = s.id;
      if (progressId != null) {
        state(type).installProgress[progressId] = 0.0;
      }

      try {
        await downloadPackageFile(
          repoClient,
          downloadUrl,
          file.path,
          onProgress: (received, total) {
            if (total != null && total > 0) {
              final fraction = received / total;
              if (progressId != null) {
                state(type).installProgress[progressId] = fraction;
              }
              report(fraction);
            }
          },
        );
      } finally {
        if (progressId != null) {
          state(type).installProgress.remove(progressId);
        }
      }

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
    });
  }

  @override
  Stream<double> updateSource(Source source) => installSource(source);

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
