import 'dart:convert';

import '../ExtensionBridge.dart';
import '../Logger.dart';

/// Sends the app's network settings (DNS-over-HTTPS, proxy, User-Agent) to
/// every running backend runtime, and again whenever the app changes them
/// ([DartotsuExtensionBridge.networkChanged]).
///
/// Each JVM backend registers how it receives the settings (its
/// `initClient` call); the JVM side rebuilds its HTTP clients from them.
class NetworkSettingsSync {
  NetworkSettingsSync._();

  static final _receivers = <Object, Future<void> Function(String data)>{};

  /// The settings as the JVM side's `Network.configure` reads them.
  static String encode() {
    final network = DartotsuExtensionBridge.context.network;
    return jsonEncode({
      'dns': network?.dns,
      'proxy': network?.proxy,
      'userAgent': network?.userAgent,
    });
  }

  /// Registers [owner]'s [send] and sends it the current settings.
  static Future<void> register(
    Object owner,
    Future<void> Function(String data) send,
  ) async {
    _receivers[owner] = send;
    await send(encode());
  }

  static void unregister(Object owner) => _receivers.remove(owner);

  /// Sends the current settings to every registered backend.
  static Future<void> broadcast() async {
    final data = encode();
    for (final entry in _receivers.entries.toList()) {
      try {
        await entry.value(data);
      } catch (e) {
        Logger.log(
          'Could not send network settings to ${entry.key.runtimeType}: $e',
        );
      }
    }
  }
}
