import 'package:dartotsu_extension_bridge/Engines/JavaEngine/Bridge/JniBridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('emptyJavaBridgeValue', () {
    test('bool', () {
      expect(emptyJavaBridgeValue<bool>(), isFalse);
    });

    test('Map<String, dynamic>', () {
      expect(emptyJavaBridgeValue<Map<String, dynamic>>(), <String, dynamic>{});
    });

    test('List<Map<String, dynamic>>', () {
      expect(
        emptyJavaBridgeValue<List<Map<String, dynamic>>>(),
        <Map<String, dynamic>>[],
      );
    });

    test('List<dynamic> - regression: getVideoList/getPageList/getPreference/'
        'getNovelContent all call bridge.call<List<dynamic>>() and used to '
        'crash here with a null cast instead of returning an empty list', () {
      expect(emptyJavaBridgeValue<List<dynamic>>(), <dynamic>[]);
    });

    test('nullable T returns null instead of an empty default', () {
      expect(emptyJavaBridgeValue<String?>(), isNull);
    });

    test('an unhandled non-nullable T fails loudly, not with a cast error', () {
      expect(() => emptyJavaBridgeValue<int>(), throwsA(isA<StateError>()));
    });
  });
}
