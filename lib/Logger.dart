import 'dartotsu_extension_bridge.dart';

class Logger {
  static void log(String message, {bool show = false}) {
    DartotsuExtensionBridge.context.onLog(message, show);
  }
}
