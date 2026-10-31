import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';

import '../../Extensions/Addon.dart';
import '../../Extensions/InstallStep.dart';
import '../../Logger.dart';
import '../../Services/Shared/DesktopCorePlugin.dart';
import 'JavaInstaller.dart';

class JvmAddon extends Addon implements PluginDependency {
  JvmAddon._() {
    runtime.state.listen((_) => _sync());
    runtime.progress.listen((_) => _sync());
    core.downloading.listen((_) => _sync());
    core.progress.listen((_) => _sync());
    core.installed.listen((_) => _sync());
    core.updateAvailable.listen((available) => hasUpdate.value = available);
  }

  static final JvmAddon instance = JvmAddon._();

  static bool get supported => !Platform.isAndroid;

  static bool get _bundlesJava =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  final DesktopCorePlugin core = DesktopCorePlugin.instance;

  final InstallStep runtime = InstallStep('jre', 'Java runtime');

  late final RxList<InstallStep> _steps = <InstallStep>[
    if (_bundlesJava) runtime,
    core.step,
  ].obs;

  @override
  List<InstallStep> get steps => _steps;

  @override
  String get id => 'jvm';

  @override
  String get name => 'Java runtime';

  @override
  IconData get icon => Icons.memory_rounded;

  @override
  String get key => core.key;

  void _sync() {
    downloading.value = runtime.active || core.downloading.value;
    final parts = [
      if (_bundlesJava) runtime.finished ? 1.0 : runtime.progress.value,
      core.installed.value && !core.downloading.value
          ? 1.0
          : core.progress.value,
    ];
    progress.value = parts.reduce((a, b) => a + b) / parts.length;
  }

  Future<bool> _runtimeReady() async {
    if (!_bundlesJava) return true;
    return await JavaRuntimeManager.getSystemJavaPath() != null ||
        await JavaRuntimeManager.getJavaPath() != null;
  }

  @override
  Future<bool> isInstalled() async =>
      await _runtimeReady() && await core.isInstalled();

  @override
  Future<List<InstallStep>> plan({
    int minimum = 0,
    bool refresh = false,
  }) async {
    if (_bundlesJava && !runtime.active) {
      final system = await JavaRuntimeManager.getSystemJavaPath() != null;
      final bundled = !system && await JavaRuntimeManager.getJavaPath() != null;
      runtime.reset(
        to: system || bundled ? StepStatus.upToDate : StepStatus.waiting,
      );
      if (system) runtime.detail.value = 'System';
      if (bundled) runtime.detail.value = 'Temurin 21';
    }
    await core.plan(minimum: minimum, refresh: refresh);
    installed.value = await isInstalled();
    return steps;
  }

  Future<void>? _runtimeJob;

  Future<void> _ensureRuntime() {
    if (!_bundlesJava) return Future.value();
    return _runtimeJob ??= _installRuntime().whenComplete(() {
      _runtimeJob = null;
    });
  }

  Future<void> _installRuntime() async {
    runtime.error.value = null;
    if (await JavaRuntimeManager.getSystemJavaPath() != null) {
      runtime.state.value = StepStatus.upToDate;
      runtime.detail.value = 'System';
      runtime.progress.value = 1;
      return;
    }
    if (await JavaRuntimeManager.getJavaPath() != null) {
      runtime.state.value = StepStatus.upToDate;
      runtime.detail.value = 'Temurin 21';
      runtime.progress.value = 1;
      return;
    }

    runtime.reset(to: StepStatus.downloading);
    var windowStart = DateTime.now();
    var windowBytes = 0;
    var lastReceived = 0;
    try {
      await JavaRuntimeManager.ensureInstalled(
        onProgress: (received, total) {
          runtime.receivedBytes.value = received;
          runtime.totalBytes.value = total;
          if (total > 0) runtime.progress.value = received / total;

          windowBytes += received - lastReceived;
          lastReceived = received;
          final elapsed = DateTime.now().difference(windowStart);
          if (elapsed >= const Duration(milliseconds: 600)) {
            final rate = windowBytes / (elapsed.inMilliseconds / 1000);
            runtime.speed.value = runtime.speed.value == 0
                ? rate
                : runtime.speed.value * 0.6 + rate * 0.4;
            windowStart = DateTime.now();
            windowBytes = 0;
          }
        },
        onExtract: () {
          runtime.state.value = StepStatus.installing;
          runtime.progress.value = 1;
          runtime.speed.value = 0;
        },
      );
      runtime.state.value = StepStatus.done;
      runtime.detail.value = 'Temurin 21';
      runtime.progress.value = 1;
    } catch (e) {
      final text = e.toString().replaceFirst('Exception: ', '');
      final cancelled = text == 'Cancelled';
      runtime.state.value = cancelled ? StepStatus.waiting : StepStatus.failed;
      runtime.error.value = cancelled ? null : text;
      runtime.speed.value = 0;
      rethrow;
    }
  }

  @override
  Future<void> ensure({int minimum = 0, bool latest = false}) async {
    await _ensureRuntime();
    await core.ensure(minimum: minimum, latest: latest);
    installed.value = true;
  }

  @override
  Future<List<String>> classpath() => core.classpath();

  @override
  Future<void> autoUpdate() => core.autoUpdate();

  @override
  void cancel() {
    if (runtime.active) JavaRuntimeManager.cancel();
    core.cancel();
  }

  @override
  Future<bool> checkForUpdate() async =>
      hasUpdate.value = await core.checkForUpdate(forceRefresh: true);

  @override
  Future<void> install() async {
    await plan();
    await ensure(latest: true);
  }

  @override
  Future<void> update() => install();

  @override
  Future<void> uninstall() async {
    try {
      await core.beforeSwap?.call();
    } catch (e) {
      Logger.log('Stopping the backends before removing the runtime: $e');
    }
    await core.delete();
    if (_bundlesJava) await JavaRuntimeManager.uninstall();
    installed.value = false;
    hasUpdate.value = false;
    await plan();
  }
}
