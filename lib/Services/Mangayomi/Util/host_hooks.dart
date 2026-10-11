/// Capabilities that need the main isolate (platform channels). Worker
/// isolates install forwarding implementations; on the main isolate these stay
/// null and the callers use the platform APIs directly.
class MangayomiHostHooks {
  static Future<String> Function()? tempDirPath;

  static Future<String> Function(
    String url,
    Map<String, String> headers,
    List<String> scripts,
    int time,
  )?
  evaluateInWebview;
}
