import 'dart:io';

import 'package:dartotsu_extension_bridge/Engines/JavaEngine/Bridge/EmbeddedJvmBridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Runs on a real iOS simulator/device via
/// `flutter test integration_test/embedded_jvm_test.dart -d <device>`.
///
/// Every backend that goes through the embedded OpenJDK Zero VM on iOS
/// (`ios/Classes/EmbeddedJvm.mm` -> `EmbeddedJvmBridge` ->
/// `EmbeddedBridge.kt`) gets its `*Desktop-plugin-ios.jar` exercised here.
/// Mangayomi/Sora/LnReader/Legado are pure-Dart and never touch this path,
/// so there's nothing iOS-JVM-specific to test for them.
///
/// The CI job (.github/workflows/build.yml, `build-ios`) builds these jars
/// with `./gradlew buildAllPlugins -PiosRuntime=true` and copies them into
/// assets/plugins/ before running this test — they are not committed to the
/// repo (see .gitignore).
///
/// ## Simulator vs. real device
///
/// `EmbeddedJvm.mm` compiles a hard `#if !TARGET_OS_SIMULATOR` split: the
/// static OpenJDK framework is only built for physical arm64 iOS hardware,
/// so every embedded-JVM operation is stubbed on the Simulator target to
/// immediately return an `EMBEDDED_JVM_ERROR`
/// ("The embedded Java runtime supports physical iOS devices only.").
/// That's by design, not a bug — and GitHub Actions has no physical iOS
/// device runners, so CI can never exercise the JVM actually booting and
/// dispatching a call. This test accepts that specific error as the correct
/// outcome on a Simulator (and still proves the whole Dart -> MethodChannel
/// -> Swift -> ObjC++ chain is wired correctly: a broken channel
/// registration would throw a *different* error or hang, not this one). On
/// a real device — plug one in and pass its id to `-d` — the same test
/// exercises the actual VM boot + jar load + dispatch.
const _backendJars = [
  'aniyomiDesktop-plugin-ios.jar',
  'cloudStreamDesktop-plugin-ios.jar',
  'ireaderDesktop-plugin-ios.jar',
  'tsundokuDesktop-plugin-ios.jar',
  'kotatsuDesktop-plugin-ios.jar',
];

const _simulatorErrorMessage = 'physical iOS devices only';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final jarName in _backendJars) {
    final backendName = jarName.replaceFirst('-plugin-ios.jar', '');

    testWidgets(
      '$backendName: embedded JVM loads the jar and dispatches real calls',
      (tester) async {
        final tempDir = await getTemporaryDirectory();
        final jarFile = File('${tempDir.path}/$jarName');

        final bytes = await rootBundle.load('assets/plugins/$jarName');
        await jarFile.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );

        final bridge = EmbeddedJvmBridge();
        addTearDown(bridge.dispose);

        try {
          await bridge.init(pluginJarPath: jarFile.path);
        } on PlatformException catch (e) {
          if (e.code == 'EMBEDDED_JVM_ERROR' &&
              (e.message?.contains(_simulatorErrorMessage) ?? false)) {
            markTestSkipped(
              'Running on a Simulator — the embedded JVM only supports '
              'physical iOS devices (see EmbeddedJvm.mm). Run this test on '
              'a real device to actually exercise the VM.',
            );
            return;
          }
          rethrow;
        }

        // Only reached on a real device. Proves the whole native path with
        // no backend-specific side effects: VM boot -> dlopen
        // OpenJDKRuntime.framework -> jar attached in its own class loader
        // -> Main.api() instantiated -> Server.handle dispatch -> response
        // back across the method channel.
        final pong = await bridge.call<String>('ping', const {}, true);
        expect(pong, 'pong');

        // Proves the fuller path every backend actually runs at app
        // startup: PlatformInit.initializeDesktop (Koin + AndroidCompat
        // bootstrap on the backend's own class loader).
        final dataDir = Directory('${tempDir.path}/$backendName-data')
          ..createSync(recursive: true);
        final initResult = await bridge.call<Map<String, dynamic>>(
          'initializeDesktop',
          {'path': dataDir.path},
          true,
        );
        expect(initResult['success'], true);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
