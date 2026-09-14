import 'package:dartotsu_extension_bridge/Extensions/Extensions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('progressStream', () {
    test('runs the operation eagerly, before any listener attaches', () async {
      // installSource()/addRepo() are routinely called fire-and-forget
      // (`onPressed: () => repo.installSource(source)`, no .listen()) - if
      // the underlying work only started on first listen (as a bare
      // async* generator would), those call sites would silently do
      // nothing.
      var started = false;

      progressStream((report) async {
        started = true;
      });

      // No listener was ever attached, but scheduleMicrotask means the
      // operation is already queued - let it run.
      await Future<void>.delayed(Duration.zero);

      expect(started, isTrue);
    });

    test('emits reported progress, then a final 1.0, then closes', () async {
      final stream = progressStream((report) async {
        report(0.25);
        report(0.75);
      });

      final events = await stream.toList();

      expect(events, [0.25, 0.75, 1.0]);
    });

    test('an operation that reports nothing still closes with a final 1.0', () {
      final stream = progressStream((report) async {});

      expect(stream, emitsInOrder([1.0, emitsDone]));
    });

    test('a thrown error is delivered to listeners and the stream closes', () {
      final stream = progressStream((report) async {
        throw Exception('boom');
      });

      expect(stream, emitsInOrder([emitsError(isException), emitsDone]));
    });

    test(
      'is broadcast - multiple listeners can observe the same run',
      () async {
        final stream = progressStream((report) async {
          report(0.5);
        });

        final first = stream.toList();
        final second = stream.toList();

        expect(await first, [0.5, 1.0]);
        expect(await second, [0.5, 1.0]);
      },
    );
  });
}
