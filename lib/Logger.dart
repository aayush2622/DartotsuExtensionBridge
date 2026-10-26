import 'dartotsu_extension_bridge.dart';

final _emoji = RegExp(
  r'(?:[\u{1F000}-\u{1FAFF}\u{2300}-\u{23FF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}\u{20E3}])+ ?',
  unicode: true,
);

/// [text] without emoji, so logs from extensions stay plain text.
String stripEmoji(String text) => text.replaceAll(_emoji, '');

class Logger {
  static void log(String message, {bool show = false}) =>
      DartotsuExtensionBridge.context.onLog(stripEmoji(message), show);
}
