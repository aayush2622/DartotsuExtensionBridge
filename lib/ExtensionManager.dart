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
  final managers = <Extension>[].obs;
  late final Rx<Extension> current;
  final key = 'currentManager';

  @override
  void onInit() {
    super.onInit();
    managers.assignAll(_extensionManagers);
    current = Rx(_findById(getVal(key)) ?? managers.first);
    current.value.initialize();
  }

  void switchManager(String id) {
    final next = _findById(id);
    if (next == null) return;
    next.initialize();
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
      throw Exception(
          'Extension manager of type $T not registered \nPerhaps $T is not supported on ${Platform.operatingSystem}?');
    }
    return result;
  }

  Extension? _findById(String? id) => managers.firstWhereOrNull(
        (m) => m.id == id,
      );
  List<Extension> get _extensionManagers {
    return [
      SoraExtensions(),
      MangayomiExtensions(),
      if (Platform.isAndroid) AniyomiExtensions(),
    ];
  }
}

extension SourceExecution on Source {
  SourceMethods get methods {
    if (this is SourceMethods) return this as SourceMethods;

    final controller = Get.find<ExtensionManager>();
    final manager = controller.current.value;
    return manager.createSourceMethods(this);
  }
}
