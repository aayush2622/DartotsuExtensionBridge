import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:http/http.dart';
import 'package:isar_community/isar.dart';

import 'AddonManager.dart';
import 'ExtensionManager.dart';
import 'Network/CloudflareSolver.dart';
import 'Network/NativeNetwork.dart';
import 'Settings/KvStore.dart';

class DartotsuExtensionBridge {
  DartotsuExtensionBridge._();

  static late final BridgeContext context;
  static bool _initialized = false;

  static Future<void> init({
    required GetDirectory getDirectory,
    Isar? isarInstance,
    BridgeNetwork? network,
    Function(String log, bool show) onLog = onLog,
  }) async {
    if (_initialized) return;

    final isar = isarInstance ?? await _openIsar(getDirectory);

    context = BridgeContext(
      isar: isar,
      getDirectory: getDirectory,
      network: network,
      onLog: onLog,
    );

    Get.put(ExtensionManager());
    unawaited(
      CloudflareSolver.quietly(() => Get.put(AddonManager()).checkForUpdates()),
    );

    _initialized = true;
  }

  static Future<Isar> _openIsar(GetDirectory getDirectory) async {
    final dir = await getDirectory(
      subPath: 'isar',
      useSystemPath: true,
      useCustomPath: false,
    );

    if (dir == null) {
      throw StateError('Isar directory could not be resolved');
    }

    return Isar.open(isarSchema, directory: dir.path);
  }

  static void _assertInitialized() {
    if (!_initialized) {
      throw StateError('DartotsuExtensionBridge.init() must be called first');
    }
  }

  static Isar get isar {
    _assertInitialized();
    return context.isar;
  }

  static const isarSchema = [KvEntrySchema];

  static void onLog(String log, bool _) {
    debugPrint('DartotsuExtensionBridge: $log');
  }

  static Future<void> networkChanged() async {
    if (!_initialized) return;
    await NativeNetwork.broadcast();
  }

  static void dispose() {
    if (_initialized) {
      _initialized = false;
      Get.find<ExtensionManager>().dispose();
    }
  }
}

Isar isar = DartotsuExtensionBridge.isar;

abstract class BridgeNetwork {
  /// Client for normal requests.
  Client get httpClient;

  /// Client without a total request timeout, for large downloads.
  Client get downloadClient => httpClient;

  String? get dns => null;

  String? get proxy => null;

  String? get userAgent => null;

  Future<String?> getCookies(String url) async => null;

  Future<void> setCookies(String url, List<String> cookies) async {}

  Future<bool> presentChallenge(Widget page) async => false;
}

typedef GetDirectory =
    Future<Directory?> Function({
      String? subPath,
      bool useCustomPath,
      bool useSystemPath,
    });

class BridgeContext {
  final Isar isar;
  final GetDirectory getDirectory;
  final BridgeNetwork? network;

  final Function(String log, bool show) onLog;

  const BridgeContext({
    required this.isar,
    required this.getDirectory,
    this.network,
    this.onLog = DartotsuExtensionBridge.onLog,
  });
}
