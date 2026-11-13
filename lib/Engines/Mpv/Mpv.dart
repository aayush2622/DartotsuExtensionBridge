import 'dart:async';

import 'package:get/get.dart';
import '../../Player/MediaKit.dart';

import '../../AddonManager.dart';
import '../../Logger.dart';
import 'MpvAddon.dart';

enum MpvPhase { idle, downloading, failed, ready }

/// The player engine's life cycle: [ensure] makes libmpv available (downloading
/// it through [MpvAddon] on first use where it is not part of the app) and
/// initialises media_kit with it. Call it before creating any `Player`.
class Mpv {
  Mpv._();

  static final phase = MpvPhase.idle.obs;
  static final error = RxnString();

  /// Download speed in bytes per second while [phase] is downloading.
  static final speed = 0.0.obs;

  static Future<bool>? _job;

  static bool get ready => phase.value == MpvPhase.ready;

  static MpvAddon? get addon => Get.isRegistered<AddonManager>()
      ? Get.find<AddonManager>().addons.whereType<MpvAddon>().firstOrNull
      : null;

  static Future<bool> ensure() {
    if (ready) return Future.value(true);
    return _job ??= _prepare().whenComplete(() => _job = null);
  }

  /// Like [ensure] but never starts a download: false when the player is not
  /// installed yet. For previews and other places that can do without it.
  static Future<bool> ensureIfInstalled() async {
    if (ready) return true;
    final mpv = addon;
    if (mpv != null && await mpv.libraryPath == null) return false;
    return ensure();
  }

  static void cancel() => addon?.cancel();

  static Future<bool> _prepare() async {
    error.value = null;
    final mpv = addon;
    StreamSubscription<int>? meter;
    try {
      var path = await mpv?.libraryPath;
      if (mpv != null && path == null) {
        phase.value = MpvPhase.downloading;
        meter = _measure(mpv);
        await mpv.install();
        path = await mpv.libraryPath;
        if (path == null) throw StateError('The player was not installed');
      }
      MediaKit.ensureInitialized(libmpv: path);
      phase.value = MpvPhase.ready;
      return true;
    } on MpvCancelled {
      phase.value = MpvPhase.idle;
      return false;
    } catch (e) {
      Logger.log('Player unavailable: $e');
      error.value = '$e';
      phase.value = MpvPhase.failed;
      return false;
    } finally {
      await meter?.cancel();
      speed.value = 0;
    }
  }

  static StreamSubscription<int> _measure(MpvAddon mpv) {
    final clock = Stopwatch()..start();
    var markAt = Duration.zero;
    var markBytes = mpv.received.value;
    return mpv.received.listen((bytes) {
      final now = clock.elapsed;
      final gap = now - markAt;
      if (gap < const Duration(milliseconds: 700)) return;
      final rate = (bytes - markBytes) / (gap.inMilliseconds / 1000);
      speed.value = speed.value == 0 ? rate : speed.value * 0.6 + rate * 0.4;
      markAt = now;
      markBytes = bytes;
    });
  }
}
