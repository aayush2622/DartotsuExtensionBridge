import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../Engines/JavaEngine/JavaBridgeServer.dart';
import '../ExtensionBridge.dart';
import '../Logger.dart';
import 'BridgeWebView.dart';
import 'CloudflareSolver.dart';
import 'MClient.dart';

/// The bridge's side of the JVM backends' network: answers their callbacks
/// (cookies, User-Agent, Cloudflare, WebView tasks, logs) and keeps their
/// HTTP settings in sync with [BridgeNetwork].
///
/// Android talks over method channels, desktop and iOS over
/// [JavaBridgeServer]. A backend calls [start] before its runtime boots
/// (the runtime may call back while starting) and [attach] once it can take
/// settings.
class NativeNetwork {
  NativeNetwork._();

  static const _networkChannel = MethodChannel('flutterKotlinBridge.network');
  static const _loggerChannel = MethodChannel('flutterKotlinBridge.logger');

  static Future<void>? _started;
  static final _receivers = <Object, Future<void> Function(String data)>{};

  static Future<void> start() => _started ??= _start();

  /// Sends [owner] the current settings now and on every
  /// [DartotsuExtensionBridge.networkChanged].
  static Future<void> attach(
    Object owner,
    Future<void> Function(String data) sendSettings,
  ) async {
    await start();
    _receivers[owner] = sendSettings;
    await sendSettings(_settings());
  }

  static void detach(Object owner) => _receivers.remove(owner);

  static Future<void> broadcast() async {
    final data = _settings();
    for (final MapEntry(key: owner, value: send)
        in _receivers.entries.toList()) {
      try {
        await send(data);
      } catch (e) {
        Logger.log(
          'Could not send network settings to ${owner.runtimeType}: $e',
        );
      }
    }
  }

  /// The settings as the JVM side's `Network.configure` reads them.
  static String _settings() {
    final network = DartotsuExtensionBridge.context.network;
    return jsonEncode({
      'dns': network?.dns,
      'proxy': network?.proxy,
      'userAgent': network?.userAgent,
    });
  }

  static Future<void> _start() async {
    if (Platform.isAndroid) {
      _loggerChannel.setMethodCallHandler((call) async {
        if (call.method == 'log') Logger.log('[KOTLIN LOGS] ${call.arguments}');
      });
      _networkChannel.setMethodCallHandler(
        (call) => _handle(call.method, call.arguments as Map),
      );
      return;
    }

    await JavaBridgeServer((method, args) async {
      if (method == 'logger') {
        Logger.log(args['message']);
        return true;
      }
      return _handle(method, args);
    }).start();
  }

  static Future<dynamic> _handle(String method, Map args) async {
    final network = DartotsuExtensionBridge.context.network;

    switch (method) {
      case 'getCookies':
        return network?.getCookies(args['url'] as String);

      case 'setCookies':
        await network?.setCookies(
          args['url'] as String,
          (args['cookies'] as List).cast<String>(),
        );
        return true;

      case 'getUserAgent':
        return bridgeUserAgent();

      case 'solveCloudflare':
        final url = Uri.tryParse(args['url'] as String? ?? '');
        if (url == null || !url.hasAuthority) return false;
        return CloudflareSolver.solve(url, retried: args['retried'] == true);

      case 'webView':
        final request = jsonDecode(args['request'] as String) as Map;
        return jsonEncode(
          await BridgeWebView.run(Map<String, dynamic>.from(request)),
        );

      default:
        throw Exception('Unknown method: $method');
    }
  }
}
