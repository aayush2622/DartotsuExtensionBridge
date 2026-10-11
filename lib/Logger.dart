import 'dartotsu_extension_bridge.dart';

class Logger {
  /// Replaces the host log callback inside worker isolates.
  static void Function(String message, bool show)? sink;

  static void log(String message, {bool show = false}) {
    final sink = Logger.sink;
    if (sink != null) return sink(message, show);
    DartotsuExtensionBridge.context.onLog(message, show);
  }
}
