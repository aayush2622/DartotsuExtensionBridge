import 'dart:io';

import 'EmbeddedJvmBridge.dart';
import 'JavaBridge.dart';
import 'SidecarBridge.dart';

/// iOS can't spawn processes, so every backend shares one in-process
/// embedded VM (each JAR in its own class loader). Desktop runs one
/// `java -jar` sidecar process per backend.
JavaBridge createJavaBridge() {
  if (Platform.isIOS) return EmbeddedJvmBridge();
  return SidecarBridge();
}
