import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../Engines/JavaEngine/Bridge/JavaBridge.dart';
import '../../ExtensionBridge.dart';
import '../../Extensions/DownloadablePlugin.dart';
import '../../Extensions/Extensions.dart';
import '../../Logger.dart';
import '../../Network/NativeNetwork.dart';
import 'DesktopCorePlugin.dart';

/// Startup and shutdown shared by every backend whose sources run on a JVM
/// runtime plugin: the plugin must be installed, it auto-updates, the
/// runtime boots with the bridge's network callbacks in place, and then
/// receives the app's network settings (again whenever they change).
mixin JvmBackend on Extension {
  Future<void> startRuntime(String pluginPath);

  Future<void> sendNetworkSettings(String data);

  void stopRuntime() {}

  Future<void> releaseRuntimeFile() async {}

  @override
  Future<bool> onInitialize() async {
    final plugin = this.plugin!;
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    plugin.onUpdated = reloadRuntime;
    plugin.beforeSwap = releaseRuntimeFile;
    unawaited(plugin.autoUpdate());

    await NativeNetwork.start();
    await _boot(plugin);
    return true;
  }

  Future<void> _boot(DownloadablePlugin plugin) async {
    await startRuntime(await plugin.getPath());
    await NativeNetwork.attach(this, sendNetworkSettings);
  }

  /// Restarts the runtime on the plugin file just downloaded, so an update
  /// applies while the app runs.
  Future<void> reloadRuntime() async {
    final plugin = this.plugin;
    if (plugin == null || !plugin.installed.value) return;
    NativeNetwork.detach(this);
    stopRuntime();
    await _boot(plugin);

    try {
      await refreshInstalled();
    } catch (e, s) {
      Logger.log(
        'Error refreshing installed extensions for $id after a runtime reload: $e\n$s',
      );
    }
  }

  @override
  void dispose() {
    plugin?.onUpdated = null;
    plugin?.beforeSwap = null;
    NativeNetwork.detach(this);
    stopRuntime();
    super.dispose();
  }
}

/// Android: the plugin is loaded into the app process over [platform].
mixin AndroidJvmBackend on JvmBackend {
  MethodChannel get platform;

  @override
  Future<void> startRuntime(String pluginPath) =>
      platform.invokeMethod('loadPlugin', {'path': pluginPath});

  @override
  Future<void> sendNetworkSettings(String data) =>
      platform.invokeMethod('initClient', data);
}

/// Desktop and iOS: the plugin runs in a [java] runtime with its data under
/// `bridge/<javaDataDir>`.
mixin DesktopJvmBackend on JvmBackend {
  JavaBridge get java;

  String get javaDataDir;

  Future<Directory?> get javaDataDirectory => DartotsuExtensionBridge.context
      .getDirectory(subPath: 'bridge/$javaDataDir');

  @override
  Future<void> startRuntime(String pluginPath) async {
    final libraries = await plugin!.installDependencies();
    if (libraries.isNotEmpty) {
      DesktopCorePlugin.instance.attach(
        this,
        release: releaseRuntimeFile,
        reload: reloadRuntime,
      );
    }
    await java.init(pluginJarPath: pluginPath, libraryJarPaths: libraries);
    final dir = await javaDataDirectory;
    await java.call<void>('initializeDesktop', {'path': dir!.path});
  }

  @override
  Future<void> sendNetworkSettings(String data) =>
      java.call<void>('initClient', {'data': data});

  @override
  void stopRuntime() {
    DesktopCorePlugin.instance.detach(this);
    java.dispose();
  }

  @override
  Future<void> releaseRuntimeFile() => java.disposeAndAwaitExit();
}
