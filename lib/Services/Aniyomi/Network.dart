import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../ExtensionBridge.dart';
import '../../Logger.dart';

class AniyomiNetwork {
  static const MethodChannel _networkChannel = MethodChannel(
    'flutterKotlinBridge.network',
  );

  static const MethodChannel _loggerChannel = MethodChannel(
    'flutterKotlinBridge.logger',
  );
  static final _context = DartotsuExtensionBridge.context;
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    _loggerChannel.setMethodCallHandler((call) async {
      if (call.method == 'log') {
        Logger.log("[KOTLIN LOGS] ${call.arguments}");
      }
    });
    _networkChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'getCookies':
          return await _context.network?.getCookies(
            call.arguments['url'] as String,
          );

        case 'setCookies':
          await _context.network?.setCookies(
            call.arguments["url"] as String,
            (call.arguments["cookies"] as List).cast<String>(),
          );
      }
    });

    if (_context.network != null) {
      await _networkChannel.invokeMethod(
        'initClient',
        jsonEncode({
          'dns': _context.network?.dns,
          'proxy': _context.network?.proxy,
        }),
      );
    }
  }
}
