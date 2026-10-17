import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../Engines/JavaEngine/Bridge/JavaBridge.dart';
import '../../ExtensionBridge.dart';
import '../../Extensions/Extensions.dart';
import '../../Network/NativeNetwork.dart';

/// Startup and shutdown shared by every backend whose sources run on a JVM
/// runtime plugin: the plugin must be installed, it auto-updates, the
/// runtime boots with the bridge's network callbacks in place, and then
/// receives the app's network settings (again whenever they change).
mixin JvmBackend on Extension {
  Future<void> startRuntime(String pluginPath);

  Future<void> sendNetworkSettings(String data);

  void stopRuntime() {}

  @override
  Future<bool> onInitialize() async {
    final plugin = this.plugin!;
    plugin.installed.value = await plugin.isInstalled();
    if (!plugin.installed.value) return false;

    unawaited(plugin.autoUpdate());

    await NativeNetwork.start();
    await startRuntime(await plugin.getPath());
    await NativeNetwork.attach(this, sendNetworkSettings);
    return true;
  }

  @override
  void dispose() {
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
    await java.init(pluginJarPath: pluginPath);
    final dir = await javaDataDirectory;
    await java.call<void>('initializeDesktop', {'path': dir!.path});
  }

  @override
  Future<void> sendNetworkSettings(String data) =>
      java.call<void>('initClient', {'data': data});

  @override
  void stopRuntime() => java.dispose();
}
