import 'dart:io';

import 'package:get/get.dart';

import 'Extensions/Extensions.dart';
import 'Extensions/SourceMethods.dart';
import 'Models/Source.dart';
import 'Services/Aniyomi/AniyomiExtensions.dart';
import 'Services/Mangayomi/MangayomiExtensions.dart';
import 'Services/Sora/SoraExtensions.dart';
import 'Settings/KvStore.dart';

class ExtensionManager extends GetxController {
  final List<Extension> managers = [];

  late final Rx<Extension> current;

  final key = 'currentManager';

  final Map<Type, SourceMethods Function(Source source)> _factories = {};

  List<Extension> get _extensionManagers => [
        SoraExtensions(),
        MangayomiExtensions(),
        if (Platform.isAndroid) AniyomiExtensions(),
      ];

  @override
  void onInit() {
    super.onInit();

    managers.addAll(_extensionManagers);

    managers.forEach(
      (ext) => _factories.addAll(ext.sourceMethodFactories),
    );
    current = Rx(_findById(getVal(key)) ?? managers.first);

    current.value.initializeInstalled();
  }

  void switchManager(String id) {
    final next = _findById(id);
    if (next == null || next == current.value) return;
    next.initializeInstalled();
    current.value = next;
    setVal(key, id);
  }

  T? find<T extends Extension>() {
    for (final manager in managers) {
      if (manager is T) return manager;
    }
    return null;
  }

  T get<T extends Extension>() {
    final result = find<T>();
    if (result == null) {
      throw Exception('Extension manager of type $T not registered\n'
          'Perhaps $T is not supported on ${Platform.operatingSystem}?');
    }
    return result;
  }

  Extension? _findById(String? id) {
    if (id == null) return null;

    for (final m in managers) {
      if (m.id == id) return m;
    }

    return null;
  }

  SourceMethods createSourceMethods(Source source) {
    final factory = _factories[source.runtimeType];

    if (factory != null) {
      return factory(source);
    }

    for (final entry in _factories.entries) {
      if (source.runtimeType == entry.key ||
          source.runtimeType.toString() == entry.key.toString()) {
        return entry.value(source);
      }
    }

    throw Exception(
      "No SourceMethods registered for ${source.runtimeType}",
    );
  }
}

extension SourceExecution on Source {
  SourceMethods get methods {
    if (this is SourceMethods) return this as SourceMethods;

    final manager = Get.find<ExtensionManager>();

    return manager.createSourceMethods(this);
  }
}
