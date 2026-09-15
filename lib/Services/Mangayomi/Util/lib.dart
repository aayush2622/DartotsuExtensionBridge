import '../Eval/dart/service.dart';
import '../Eval/javascript/service.dart';
import '../Models/Source.dart';
import 'interface.dart';

class _CachedService {
  final ExtensionService service;
  final String sourceCode;
  _CachedService(this.service, this.sourceCode);
}

final _serviceCache = <String, _CachedService>{};

ExtensionService getExtensionService(MSource source) {
  final key = source.id;
  if (key == null || key.isEmpty) {
    return _createExtensionService(source);
  }

  final cached = _serviceCache[key];
  if (cached != null && cached.sourceCode == (source.sourceCode ?? '')) {
    cached.service.source = source;
    return cached.service;
  }

  cached?.service.dispose();
  final service = _createExtensionService(source);
  _serviceCache[key] = _CachedService(service, source.sourceCode ?? '');
  return service;
}

void releaseExtensionService(MSource source, ExtensionService service) {
  final key = source.id;
  if (key == null || key.isEmpty || _serviceCache[key]?.service != service) {
    service.dispose();
  }
}

void invalidateExtensionService(String? sourceId) {
  if (sourceId == null || sourceId.isEmpty) return;
  _serviceCache.remove(sourceId)?.service.dispose();
}

void disposeAllExtensionServices() {
  for (final cached in _serviceCache.values) {
    cached.service.dispose();
  }
  _serviceCache.clear();
}

ExtensionService _createExtensionService(MSource source) =>
    switch (source.sourceCodeLanguage) {
      SourceCodeLanguage.dart => DartExtensionService(source),
      SourceCodeLanguage.javascript => JsExtensionService(source),
    };
