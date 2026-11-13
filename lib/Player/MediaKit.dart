import 'Engine/NativePlayer.dart';

/// Initialises the player engine. Call [ensureInitialized] once before creating
/// any `Player`; pass the path of the libmpv to load, or leave it null to use
/// the one bundled with the app (macOS and iOS) or named by
/// `LIBMPV_LIBRARY_PATH`.
abstract class MediaKit {
  static bool _initialized = false;

  static void ensureInitialized({String? libmpv}) {
    if (_initialized) return;
    nativeEnsureInitialized(libmpv: libmpv);
    _initialized = true;
  }
}
