import 'package:dartotsu_extension_bridge/Services/Mangayomi/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Services/Mangayomi/Util/lib.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MSource source({required String id, String code = 'code-v1'}) => MSource(
    id: id,
    sourceCode: code,
    sourceCodeLanguage: SourceCodeLanguage.dart,
  );

  test('reuses the same service instance across calls for the same source', () {
    final s = source(id: 'src-1');

    final a = getExtensionService(s);
    final b = getExtensionService(s);

    expect(identical(a, b), isTrue);
  });

  test('rebuilds when the source code changes (in-place update)', () {
    final s = source(id: 'src-2');
    final before = getExtensionService(s);

    s.sourceCode = 'code-v2';
    final after = getExtensionService(s);

    expect(identical(before, after), isFalse);
  });

  test('releaseExtensionService keeps a cached instance alive for reuse', () {
    final s = source(id: 'src-3');
    final service = getExtensionService(s);

    releaseExtensionService(s, service);

    expect(identical(getExtensionService(s), service), isTrue);
  });

  test(
    'releaseExtensionService disposes an uncached instance (no source id)',
    () {
      final s = source(id: '');
      final a = getExtensionService(s);
      final b = getExtensionService(s);

      expect(identical(a, b), isFalse);

      releaseExtensionService(s, a);
    },
  );

  test('invalidateExtensionService evicts so the next call rebuilds', () {
    final s = source(id: 'src-4');
    final before = getExtensionService(s);

    invalidateExtensionService(s.id);
    final after = getExtensionService(s);

    expect(identical(before, after), isFalse);
  });

  test('different source ids never share a cached instance', () {
    final a = getExtensionService(source(id: 'src-5a'));
    final b = getExtensionService(source(id: 'src-5b'));

    expect(identical(a, b), isFalse);
  });

  test('disposeAllExtensionServices evicts every cached entry', () {
    final s = source(id: 'src-6');
    final before = getExtensionService(s);

    disposeAllExtensionServices();
    final after = getExtensionService(s);

    expect(identical(before, after), isFalse);
  });
}
