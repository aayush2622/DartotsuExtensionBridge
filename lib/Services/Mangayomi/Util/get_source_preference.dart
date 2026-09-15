import '../Eval/dart/model/source_preference.dart';
import '../Models/Source.dart';
import 'lib.dart';

List<SourcePreference> getSourcePreference({required MSource source}) {
  final service = getExtensionService(source);

  try {
    return service.getSourcePreferences();
  } finally {
    releaseExtensionService(source, service);
  }
}
