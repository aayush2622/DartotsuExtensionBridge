import 'dart:io';

import 'EmbeddedJvmBridge.dart';
import 'JniBridge.dart' show JavaBridge;
import 'SidecarBridge.dart';

/// Picks the [JavaBridge] the current platform can actually run.
///
/// * **iOS** — no `Process.start`, no JIT: an embedded interpreter-only
///   OpenJDK Zero VM ([EmbeddedJvmBridge]).
/// * **Windows / Linux / macOS** — a `java -jar` subprocess ([SidecarBridge]).
///
/// [JniBridge] (in-process JVM via `package:jni`) is kept for reference but is
/// not selected here; it needs a real `libjvm` and only one instance per
/// process.
JavaBridge createJavaBridge() {
  if (Platform.isIOS) return EmbeddedJvmBridge();
  return SidecarBridge();
}
