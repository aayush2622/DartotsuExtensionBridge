import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:install_plugin/install_plugin.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../Logger.dart';
import '../../Settings/KvStore.dart';
import '../../dartotsu_extension_bridge.dart';
import 'PackagedSource.dart';

mixin AndroidApkInstallMixin on Extension {
  http.Client get repoClient;

  MethodChannel get platform;

  String get installPrivateKey;

  String get androidExtensionsDirName;

  Future<Directory?> _extensionsDir(ItemType type) =>
      DartotsuExtensionBridge.context.getDirectory(
        subPath: 'bridge/$androidExtensionsDirName/${type.toString()}',
        useSystemPath: false,
        useCustomPath: true,
      );

  final Map<String, Stream<double>> _installsInFlight = {};

  @override
  Stream<double> installSource(Source source) {
    final id = (source as PackagedSource).id;

    if (id != null) {
      final inFlight = _installsInFlight[id];
      if (inFlight != null) return inFlight;
    }

    final stream = progressStream((report) async {
      try {
        await _installSourceImpl(source, report);
      } finally {
        if (id != null) _installsInFlight.remove(id);
      }
    });

    if (id != null) {
      _installsInFlight[id] = stream;
    }

    return stream;
  }

  Future<void> _writeWithProgress(
    http.StreamedResponse response,
    File file,
    String? progressId,
    ItemType type,
    void Function(double) report,
  ) async {
    final sink = file.openWrite();
    final total = response.contentLength;
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;

        if (total != null && total > 0) {
          final fraction = received / total;
          if (progressId != null) {
            state(type).installProgress[progressId] = fraction;
          }
          report(fraction);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<void> _installSourceImpl(
    Source source,
    void Function(double) report,
  ) async {
    final s = source as PackagedSource;
    final isPrivate = getVal(installPrivateKey) ?? false;
    final type = source.itemType!;
    if (s.apkUrl == null) {
      throw Exception('Source APK URL is required for installation.');
    }

    final progressId = s.id;
    if (progressId != null) {
      state(type).installProgress[progressId] = 0.0;
    }

    try {
      final packageName =
          s.pkgName ?? s.apkUrl!.split('/').last.replaceAll('.apk', '');

      final apkFileName = '$packageName.apk';

      final request = http.Request('GET', Uri.parse(s.apkUrl!));

      final response = await repoClient.send(request);

      if (response.statusCode != 200) {
        throw Exception('Extension download failed (${response.statusCode})');
      }

      if (isPrivate) {
        final extDir = await _extensionsDir(type);

        if (extDir == null) {
          throw Exception('Failed to get extension directory');
        }

        await extDir.create(recursive: true);

        final file = File(p.join(extDir.path, apkFileName));

        await _writeWithProgress(response, file, progressId, type, report);

        Logger.log('Installed PRIVATE extension: ${s.pkgName}');
      } else {
        final tempDir = await getTemporaryDirectory();

        final apkFile = File(p.join(tempDir.path, apkFileName));

        await _writeWithProgress(response, apkFile, progressId, type, report);

        final result = await InstallPlugin.installApk(
          apkFile.path,
          appId: packageName,
        );

        if (await apkFile.exists()) {
          await apkFile.delete();
        }

        if (result['isSuccess'] != true) {
          throw Exception(
            'Installation failed: '
            '${result['errorMessage'] ?? 'Unknown error'}',
          );
        }

        Logger.log('Installed SHARED extension: $packageName');
      }

      final avail = state(type).available;

      avail.value = avail.value.where((e) => e.id != s.id).toList();
      await fetchInstalledExtensions(type);
      final raw = state(type).rawAvailable.value;
      detectUpdates(raw, type);
    } catch (e) {
      Logger.log('Error installing source: $e');
      rethrow;
    } finally {
      if (progressId != null) {
        state(type).installProgress.remove(progressId);
      }
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as PackagedSource;
    final type = source.itemType!;
    final fallbackPkg =
        s.pkgName ??
        s.apkName?.replaceAll('.apk', '') ??
        s.apkUrl?.split('/').last.replaceAll('.apk', '') ??
        s.id ??
        '';
    try {
      if (s.isShared == false) {
        final baseDir = await _extensionsDir(type);

        final apkFileName = s.apkPath != null
            ? p.basename(s.apkPath!)
            : (s.apkName ?? '$fallbackPkg.apk');
        final file = File(p.join(baseDir!.path, apkFileName));

        if (await file.exists()) {
          await file.delete();
          Logger.log('Deleted private extension: ${s.pkgName}');
        } else {
          Logger.log('Private extension file not found: ${s.pkgName}');
        }

        _refreshAvailable(type);
        await fetchInstalledExtensions(type);
        detectUpdates(state(type).rawAvailable.value, type);
        return;
      }

      final packageName = s.pkgName;
      if (packageName == null || packageName.isEmpty) {
        throw Exception('Package name is required for uninstall.');
      }

      final isInstalled =
          await InstalledApps.isAppInstalled(packageName) ?? false;

      if (!isInstalled) {
        state(type).installed.value = state(
          type,
        ).installed.value.where((e) => e.id != s.id).toList();

        _refreshAvailable(type);
        await fetchInstalledExtensions(type);
        detectUpdates(state(type).rawAvailable.value, type);
        return;
      }

      final success = await InstalledApps.uninstallApp(packageName) ?? false;
      if (!success) {
        throw Exception('Failed to initiate uninstallation for: $packageName');
      }

      final timeout = const Duration(seconds: 10);
      final start = DateTime.now();

      while (DateTime.now().difference(start) < timeout) {
        final stillInstalled =
            await InstalledApps.isAppInstalled(packageName) ?? false;
        if (!stillInstalled) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final finalCheck =
          await InstalledApps.isAppInstalled(packageName) ?? false;
      if (finalCheck) {
        throw Exception('Uninstallation timed out or was cancelled by user.');
      }

      Logger.log('Uninstalled shared extension: $packageName');

      _refreshAvailable(type);
      await fetchInstalledExtensions(type);
      detectUpdates(state(type).rawAvailable.value, type);
    } catch (e) {
      Logger.log('Error uninstalling source: $e');
      rethrow;
    }
  }

  void _refreshAvailable(ItemType type) {
    final raw = state(type).rawAvailable.value;
    final installedIds = state(type).installed.value.map((e) => e.id).toSet();

    state(type).available.value = List.unmodifiable(
      raw.where((e) => !installedIds.contains(e.id)),
    );
  }

  @override
  Stream<double> updateSource(Source source) => installSource(source);

  Future<List<T>> loadInstalledAndroidSources<T extends PackagedSource>(
    String method,
    ItemType type,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final dir = await _extensionsDir(type);
      final jsonString = await platform.invokeMethod<String>(method, dir?.path);

      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> result = jsonDecode(jsonString);

      return result
          .map((e) => fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.itemType == type)
          .toList(growable: false);
    } catch (e) {
      return [];
    }
  }
}
