import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../Engines/JavaEngine/Bridge/JniBridge.dart';
import '../../Logger.dart';
import '../../dartotsu_extension_bridge.dart';
import 'PackagedSource.dart';
import 'TachiyomiRepo.dart';

/// `installSource` / `updateSource` / `uninstallSource` — and installed-source
/// loading — for the desktop (JVM-sidecar) Tachiyomi backends: Aniyomi,
/// IReader and Tsundoku.
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

  /// JVM sidecar bridge used to call `getInstalled…Extensions` in
  /// [loadInstalledJniSources].
  JavaBridge get jni;

  Future<Directory?> _extensionsDir(ItemType type) =>
      DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/$jniDataDir/extensions/${type.toString()}',
        useSystemPath: false,
        useCustomPath: true,
      );

  /// Calls [jniMethod] over the JVM sidecar to load installed [type] sources,
  /// then dedupes and prunes the result — the three desktop backends'
  /// `_loadInstalled` were byte-identical past the JNI method name and the
  /// concrete [PackagedSource] subtype ([fromJson]).
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

  /// The native loader keeps only the highest-versioned file per package
  /// when scanning (`byPackage` in AnimeExtensionLoader.desktop.kt /
  /// MangaExtensionLoader.desktop.kt), so a superseded version that
  /// installSource failed to delete never shows up in the list - but it
  /// also never gets deleted, so old package files pile up in the
  /// extensions directory indefinitely across app restarts. Sweep anything
  /// that isn't the file currently backing an installed source.
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

  /// Guards against duplicate-`GlobalKey` crashes in the extension list UI
  /// (each entry is keyed by [Source.id]). A native-side scan glitch -
  /// e.g. a leftover jar from an update that failed to clean up its old
  /// file, or an entry whose id couldn't be parsed - can otherwise surface
  /// two [Source]s sharing an id. Drops entries with a blank/missing id and
  /// keeps the highest-versioned entry per remaining id.
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

      // Capture the path of the version currently on disk (if any) before we
      // overwrite the field, so a rename between versions doesn't orphan a
      // jar.
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
