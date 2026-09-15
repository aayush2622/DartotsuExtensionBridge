import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:http/http.dart';
import 'package:isar_community/isar.dart';

import 'AddonManager.dart';
import 'ExtensionManager.dart';
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
  /// [network] is an optional network interface for DNS, proxy, and cookie management.
  /// [onLog] is a callback for logging messages, defaulting to printing to the console.
  static Future<void> init({
    required GetDirectory getDirectory,
    Client? http,
    Isar? isarInstance,
    BridgeNetwork? network,
    Function(String log, bool show) onLog = onLog,
  }) async {
    if (_initialized) return;

    final isar = isarInstance ?? await _openIsar(getDirectory);

    context = BridgeContext(
      isar: isar,
      http: http,
      getDirectory: getDirectory,
      network: network,
      onLog: onLog,
    );

    Get.put(ExtensionManager());
    unawaited(Get.put(AddonManager()).checkForUpdates());

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

  static void dispose() {
    if (_initialized) {
      _initialized = false;
      Get.find<ExtensionManager>().dispose();
    }
  }
}

Isar isar = DartotsuExtensionBridge.isar;

abstract interface class BridgeNetwork {
  /// DNS-over-HTTPS resolver endpoint (e.g. `https://cloudflare-dns.com/dns-query`),
  /// or `null` to use the platform's normal DNS resolution.
  String? get dns;

  /// `host:port` of an HTTP proxy to route requests through, or `null` for none.
  String? get proxy;

  /// The `User-Agent` header every backend should send by default, or `null`
  /// to leave a backend's own default untouched.
  String? get userAgent;

  /// Returns cookies valid for [url] as a JSON-encoded array of
  /// `{name, value, domain, hostOnly, path, expires, secure, httpOnly}`
  /// objects (the shape the native `CookieInterceptor` in `runtimeManager`
  /// also expects), or `null`/empty for none.
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
  final GetDirectory getDirectory;
  final BridgeNetwork? network;

  final Function(String log, bool show) onLog;

  const BridgeContext({
    required this.isar,
    this.http,
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
