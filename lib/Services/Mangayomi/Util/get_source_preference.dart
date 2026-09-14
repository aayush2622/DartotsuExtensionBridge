import '../Eval/dart/model/source_preference.dart';
import '../Eval/dart/service.dart';
import '../Eval/javascript/service.dart';
import '../Models/Source.dart';
import 'interface.dart';

List<SourcePreference> getSourcePreference({required MSource source}) {
  final ExtensionService service =
      source.sourceCodeLanguage == SourceCodeLanguage.dart
      ? DartExtensionService(source)
      : JsExtensionService(source);

  try {
    return service.getSourcePreferences();
  } finally {
    service.dispose();
  }
}
