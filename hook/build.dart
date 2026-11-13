import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart' as p;

import 'src/apple.dart';
import 'src/bundles.dart';

/// Native assets of the player engine.
///
/// `hooks.user_defines.dartotsu_extension_bridge.source` picks where libmpv
/// comes from: `bundled` (default, inside the app), `external` (not part of the
/// app on Android, Linux and Windows: `MpvAddon` downloads it on first use and
/// `Mpv.ensure()` hands its path to the player; Android still bundles the small
/// JNI helper, other targets treat it as `bundled`), `system` (Linux and
/// Windows, a library found by the loader) or `local` (a directory given by
/// `library-directory`).
void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    final architecture = input.config.code.targetArchitecture;
    final catalogFile = File.fromUri(
      input.packageRoot.resolve('hook/native_bundles.json'),
    );
    final catalog = await Bundle.read(catalogFile);
    output.dependencies.add(catalogFile.uri);
    final target = '${os.name}_${architecture.name}';
    final bundle = catalog[target];
    if (bundle == null) {
      throw UnsupportedError('No player native bundle for $target');
    }

    var source = input.userDefines['source'] ?? 'bundled';
    final external =
        source == 'external' &&
        (os == OS.android || os == OS.linux || os == OS.windows);
    if (source == 'external') source = 'bundled';

    if (external && os != OS.android) {
      // Nothing to bundle: libmpv is loaded from the downloaded file.
    } else if (source == 'system') {
      if (os != OS.linux && os != OS.windows) {
        throw UnsupportedError(
          'System libmpv is supported on Linux and Windows only',
        );
      }
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'libmpv',
          linkMode: DynamicLoadingSystem(Uri(path: bundle.library)),
        ),
      );
    } else {
      final Directory directory;
      if (source == 'local') {
        final path = input.userDefines.path('library-directory');
        if (path == null) {
          throw ArgumentError('source: local requires library-directory');
        }
        directory = Directory.fromUri(path);
        await for (final entity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) output.dependencies.add(entity.uri);
        }
      } else if (source == 'bundled') {
        final cache = BundleCache(
          Directory.fromUri(
            input.userDefines.path('cache-directory') ??
                input.outputDirectoryShared.resolve('prebuilt/'),
          ),
        );
        final extracted = await cache.prepare(bundle);
        directory = bundle.root == null
            ? extracted
            : Directory(p.join(extracted.path, bundle.root));
      } else {
        throw ArgumentError('Unknown player source: $source');
      }
      final libraries = bundle.xcframework
          ? await prepareAppleLibraries(
              directory,
              Directory.fromUri(input.outputDirectory.resolve('frameworks/')),
              os.name,
              architecture == Architecture.x64 ? 'x86_64' : 'arm64',
              simulator:
                  os == OS.iOS &&
                  input.config.code.iOS.targetSdk == IOSSdk.iPhoneSimulator,
            )
          : await selectLibraries(directory, bundle.library);
      if (external) {
        libraries.removeWhere((f) => p.basename(f.path) == bundle.library);
      }
      if (os == OS.android &&
          !libraries.any(
            (file) => p.basename(file.path) == 'libmediakitandroidhelper.so',
          )) {
        throw StateError(
          'Android requires libmediakitandroidhelper.so alongside libmpv.so',
        );
      }
      for (final library in libraries) {
        final basename = p.basename(library.path);
        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: basename == bundle.library ? 'libmpv' : 'native/$basename',
            linkMode: DynamicLoadingBundled(),
            file: library.uri,
          ),
        );
        output.dependencies.add(library.uri);
      }
    }
    await CBuilder.library(
      name: 'dartotsu_mpv_loop',
      assetName: 'Player/Engine/Core/NativeEventLoopBindings.dart',
      sources: ['native/mpv/native_event_loop.c', 'native/mpv/native_library.c'],
      includes: [
        File(
          Platform.resolvedExecutable,
        ).parent.parent.uri.resolve('include/').toFilePath(),
      ],
      libraries: [
        if (os == OS.linux) ...['pthread', 'dl'],
        if (os == OS.android) 'dl',
      ],
    ).run(input: input, output: output);
  });
}
