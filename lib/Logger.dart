import 'package:flutter/services.dart';

import 'dartotsu_extension_bridge.dart';

class Logger {
  static void init() => initKotlinLogging();

  static void log(String message, {bool show = false}) {
    DartotsuExtensionBridge.onLog(message, show);
  }

  static void initKotlinLogging() {
    var channel = const MethodChannel('flutterKotlinBridge.logger');
    channel.setMethodCallHandler(
      (call) async {
        if (call.method == 'log') {
          log("[KOTLIN LOGS] ${call.arguments}");
        }
      },
    );
  }
}
