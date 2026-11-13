import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:dartotsu_extension_bridge/player.dart';
import 'package:dartotsu_extension_bridge/Player/Engine/Core/NativeLibrary.dart';

void main() {
  final lib = Platform.environment['LIBMPV_LIBRARY_PATH'];
  test('a generated source plays and reports its state', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final clock = Stopwatch()..start();
    MediaKit.ensureInitialized(libmpv: lib);
    final init = clock.elapsedMilliseconds;
    final player = Player(
      configuration: const PlayerConfiguration(muted: true),
    );
    final created = clock.elapsedMilliseconds;
    await (player.platform as NativePlayer).setProperty('ao', 'null');
    await player.open(
      Media(File('test/fixtures/tone.wav').absolute.path),
      play: true,
    );
    final duration = await player.stream.duration
        .firstWhere((d) => d > Duration.zero)
        .timeout(const Duration(seconds: 20));
    final firstFrame = clock.elapsedMilliseconds;
    await player.stream.position
        .firstWhere((p) => p > const Duration(milliseconds: 400))
        .timeout(const Duration(seconds: 20));
    await player.seek(const Duration(seconds: 2));
    expect(player.state.width ?? 0, greaterThanOrEqualTo(0));
    // ignore: avoid_print
    print(
      'ensureInitialized ${init}ms, Player() ${created - init}ms, '
      'open to duration ${firstFrame - created}ms, duration $duration',
    );
    await player.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('players do not share a lock and track changes do not block', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized(libmpv: lib);
    final a = Player(configuration: const PlayerConfiguration(muted: true));
    final b = Player(configuration: const PlayerConfiguration(muted: true));
    final first = a.platform as NativePlayer;
    final second = b.platform as NativePlayer;
    expect(identical(first.lock, second.lock), isFalse);
    await first.setProperty('ao', 'null');
    await a.open(
      Media(File('test/fixtures/tone.wav').absolute.path),
      play: true,
    );
    await a.stream.duration
        .firstWhere((d) => d > Duration.zero)
        .timeout(const Duration(seconds: 20));
    final clock = Stopwatch()..start();
    await a.setAudioTrack(
      AudioTrack.uri('http://10.255.255.1/missing.mp3', title: 'remote'),
    );
    await a.pause();
    expect(clock.elapsedMilliseconds, lessThan(1500));
    await a.dispose();
    await b.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'a player is created even when the process numeric locale is not C',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final setlocale = DynamicLibrary.process()
          .lookupFunction<
            Pointer<Utf8> Function(Int32, Pointer<Utf8>),
            Pointer<Utf8> Function(int, Pointer<Utf8>)
          >('setlocale');
      const numeric = 1;
      final name = 'en_IN.utf8'.toNativeUtf8();
      try {
        if (setlocale(numeric, name) == nullptr) {
          markTestSkipped('the en_IN locale is not installed');
          return;
        }
        MediaKit.ensureInitialized(libmpv: lib);
        final player = Player(
          configuration: const PlayerConfiguration(muted: true),
        );
        await (player.platform as NativePlayer).setProperty('ao', 'null');
        await player.dispose();
      } finally {
        calloc.free(name);
      }
    },
    skip: !Platform.isLinux,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('initialising again without a path keeps the path that was given', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final link = Link(
      '${Directory.systemTemp.createTempSync('libmpv').path}/libmpv.so.2',
    )..createSync(lib!);
    NativeLibrary.ensureInitialized(libmpv: link.path);
    NativeLibrary.ensureInitialized();
    expect(NativeLibrary.path, link.path);
  }, skip: lib == null || !Platform.isLinux);
}
