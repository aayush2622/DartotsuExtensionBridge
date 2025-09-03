import 'Eval/dart/service.dart';
import 'Eval/javascript/service.dart';
import 'Models/Source.dart';
import 'interface.dart';

ExtensionService getExtensionService(MSource source) {
  return switch (source.sourceCodeLanguage) {
    SourceCodeLanguage.dart => DartExtensionService(source),
    SourceCodeLanguage.javascript => JsExtensionService(source),
    _ => throw UnimplementedError(
        "Unsupported source code language: ${source.sourceCodeLanguage}"),
  };
}

