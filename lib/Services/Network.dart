import 'dart:io';

import 'package:flutter/services.dart';

import '../Engines/JavaEngine/JavaBridgeServer.dart';
import '../ExtensionBridge.dart';
import '../Logger.dart';

class BridgeChannels {
  static const _networkChannel = MethodChannel('flutterKotlinBridge.network');

  static const _loggerChannel = MethodChannel('flutterKotlinBridge.logger');

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized || Platform.isIOS) return;

    _initialized = true;

    if (Platform.isAndroid) {
      await _initAndroid();
    } else {
      await _initDesktop();
    }
  }

  static Future<dynamic> _handleNetworkCall(
    String method,
    Map<dynamic, dynamic> args,
  ) async {
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

      default:
        throw Exception('Unknown method: $method');
    }
  }

  static Future<void> _initAndroid() async {
    _loggerChannel.setMethodCallHandler((call) async {
      if (call.method == 'log') {
        Logger.log('[KOTLIN LOGS] ${call.arguments}');
      }
    });

    _networkChannel.setMethodCallHandler(
      (call) => _handleNetworkCall(
        call.method,
        call.arguments as Map<dynamic, dynamic>,
      ),
    );
  }

  static Future<void> _initDesktop() async {
    await JavaBridgeServer((method, args) async {
      if (method == 'logger') {
        Logger.log(args['message']);
        return true;
      }

      return _handleNetworkCall(method, args);
    }).start();
  }
}
