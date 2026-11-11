import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../Engines/JavaEngine/Bridge/JavaBridge.dart';
import '../../Logger.dart';
import '../../Network/MClient.dart';
import '../../dartotsu_extension_bridge.dart';
import 'PackagedSource.dart';
import 'TachiyomiRepo.dart';

mixin TachiyomiJavaDesktopExtension on Extension {
  http.Client get repoClient;

  String get javaDataDir;

  JavaBridge get java;

  Future<Directory?> _extensionsDir(ItemType type) =>
      DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/$javaDataDir/extensions/${type.toString()}',
        useSystemPath: false,
        useCustomPath: true,
      );

  Future<List<T>> loadInstalledJavaSources<T extends PackagedSource>(
    String javaMethod,
    ItemType type,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final dir = await _extensionsDir(type);
      final scanned = await _packageFiles(dir!);

      final result = await java.call<List<Map<String, dynamic>>>(javaMethod, {
        "path": dir.path,
      });

      final sources = result.map(fromJson).where((s) => s.itemType == type);

      final deduped = _dedupeById(sources);
      if (deduped.isNotEmpty) {
        await _pruneObsoletePackageFiles(scanned, deduped);
      }
      return deduped;
    } catch (e, s) {
      Logger.log("Desktop loadInstalled error: $e\n$s");
      return [];
    }
  }

  Future<Set<String>> _packageFiles(Directory dir) async {
    if (!await dir.exists()) return {};
    return {
      await for (final entry in dir.list())
        if (entry is File && p.extension(entry.path) == '.apk') entry.path,
    };
  }

  Future<void> _pruneObsoletePackageFiles(
    Set<String> scanned,
    List<PackagedSource> installed,
  ) async {
    final keep = installed
        .map((s) => s.apkPath)
        .whereType<String>()
        .map(p.basename)
        .toSet();

    // `<package>-v<version>.apk` -> `<package>`.
    String stem(String name) =>
        p.basename(name).replaceFirst(RegExp(r'-v[\d.]+\.apk$'), '');
    final keepStems = keep.map(stem).toSet();

    for (final path in scanned) {
      if (keep.contains(p.basename(path))) continue;
      // An apk that failed to load is not a duplicate of a loaded one; it
      // stays so it can be tried again instead of the extension vanishing.
      if (!keepStems.contains(stem(path))) continue;

      try {
        final file = File(path);
        if (!await file.exists()) continue;
        await file.delete();
        Logger.log('Deleted obsolete extension file: $path');
      } catch (e) {
        Logger.log('Failed to delete obsolete extension file $path: $e');
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
          MClient.download(),
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

      final avail = state(type).available;
      avail.value = avail.value.where((e) => e.id != s.id).toList();
      await fetchInstalledExtensions(type);
      if (!state(type).installed.value.any((e) => e.id == s.id)) {
        // Keep the version that worked: drop the new file, bring the old back.
        if (oldApkPath != null && oldApkPath != file.path) {
          s.apkPath = oldApkPath;
          try {
            if (await file.exists()) await file.delete();
          } catch (e) {
            Logger.log('Could not remove ${file.path}: $e');
          }
          await fetchInstalledExtensions(type);
        }
        throw Exception(
          'The Java engine could not load ${s.name ?? 'the extension'}',
        );
      }

      if (oldApkPath != null && oldApkPath != file.path) {
        try {
          final oldFile = File(oldApkPath);
          if (await oldFile.exists()) {
            await oldFile.delete();
            Logger.log('Deleted old extension: ${oldFile.path}');
          }
        } catch (e) {
          Logger.log('Could not delete the old extension $oldApkPath: $e');
        }
      }
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
