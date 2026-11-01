import 'dart:async';

/// Global download pacer. The host sets [limitKbps] (0 = unlimited).
class DownloadThrottle {
  DownloadThrottle._();

  static int Function() limitKbps = () => 0;

  static int _clock = 0;

  static Future<void> take(int bytes) async {
    final limit = limitKbps() * 1024;
    if (limit <= 0) {
      _clock = 0;
      return;
    }
    final now = DateTime.now().microsecondsSinceEpoch;
    if (_clock < now) _clock = now;
    _clock += bytes * 1000000 ~/ limit;
    final wait = _clock - now;
    if (wait > 50000) {
      await Future<void>.delayed(Duration(microseconds: wait));
    }
  }
}
