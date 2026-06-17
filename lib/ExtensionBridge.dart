import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:http/http.dart';
import 'package:isar_community/isar.dart';

import 'ExtensionManager.dart';
import 'Services/LnReader/JsEngine/JsEngine.dart';
import 'Settings/KvStore.dart';

class DartotsuExtensionBridge {
  DartotsuExtensionBridge._();

  static late final BridgeContext context;
  static bool _initialized = false;

  /// Initializes the Dartotsu Extension Bridge.
  ///
  /// [getDirectory] is required to resolve directories for Isar and WebView data.
  /// {@macro get_directory_contract}
  ///
  /// [http] is an optional HTTP client for network requests.
  ///
  /// [isarInstance] provides your Isar client and must include [isarSchema].
  /// If omitted, a new instance will be initialized internally.
  static Future<void> init({
    required GetDirectory getDirectory,
    Client? http,
    Isar? isarInstance,
    BridgeNetwork? network,
    Function(String log, bool show) onLog = onLog,
  }) async {
    if (_initialized) return;

    final isar = isarInstance ?? await _openIsar(getDirectory);

    final webViewEnv = Platform.isWindows
        ? await _createWebViewEnv(getDirectory)
        : null;

    context = BridgeContext(
      isar: isar,
      http: http,
      webViewEnvironment: webViewEnv,
      getDirectory: getDirectory,
      network: network,
      onLog: onLog,
    );

    Get.put(ExtensionManager());
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

  static Future<WebViewEnvironment?> _createWebViewEnv(
      GetDirectory getDirectory,) async {
    try {
      final version = await WebViewEnvironment.getAvailableVersion();
      if (version == null) return null;

      final dir = await getDirectory(
        subPath: 'webview',
        useSystemPath: true,
        useCustomPath: false,
      );

      if (dir == null) return null;

      return WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: dir.path),
      );
    } catch (e, st) {
      debugPrint("Failed to create WebView environment: $e\n$st");
      return null;
    }
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

  static void dispose() {
    if (_initialized) {
      _initialized = false;
      Get.find<ExtensionManager>().dispose();
      JsExtensionEngine.instance.dispose();
    }
  }
}

Isar isar = DartotsuExtensionBridge.isar;

abstract interface class BridgeNetwork {
  String? get dns;

  String? get proxy;

  Future<String?> getCookies(String url);

  Future<void> setCookies(String url, List<String> cookies);
}

/// {@macro get_directory_contract}
typedef GetDirectory =
Future<Directory?> Function({
String? subPath,
bool useCustomPath,
bool useSystemPath,
});

class BridgeContext {
  final Isar isar;
  final Client? http;
  final WebViewEnvironment? webViewEnvironment;
  final GetDirectory getDirectory;
  final BridgeNetwork? network;

  final Function(String log, bool show) onLog;

  const BridgeContext({
    required this.isar,
    this.http,
    this.webViewEnvironment,
    required this.getDirectory,
    this.network,
    this.onLog = DartotsuExtensionBridge.onLog,
  });
}

/// {@template get_directory_contract}
/// Resolves directories used by the Dartotsu Extension Bridge.
///
/// Implementations must:
/// - Return a stable, persistent directory
/// - Create the directory if it does not exist
/// - Respect `subPath`, `useCustomPath`, and `useSystemPath`
///
/// ### Example
///
/// ```dart
/// Future<Directory?> getDirectory({
///   String? subPath,
///   bool useCustomPath = false,
///   bool useSystemPath = false,
/// }) async {
///   final base = await getApplicationSupportDirectory();
///   final dir = subPath != null
///       ? Directory('${base.path}/$subPath')
///       : base;
///
///   if (!await dir.exists()) {
///     await dir.create(recursive: true);
///   }
///
///   return dir;
/// }
/// ```
/// {@endtemplate}
