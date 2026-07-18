import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import 'Extensions/Extensions.dart';
import 'Extensions/SourceMethods.dart';
import 'Models/Source.dart';
import 'Services/Aniyomi/AniyomiAndroid/AniyomiExtensions.dart';
import 'Services/Aniyomi/AniyomiDesktop/AniyomiDesktopExtensions.dart';
import 'Services/CloudStream/CloudStreamAndroid/CloudStreamExtensions.dart';
import 'Services/CloudStream/CloudStreamDesktop/CloudStreamDesktopExtensions.dart';
import 'Services/IReader/IreaderAndroid/IReaderExtensions.dart';
import 'Services/IReader/IreaderDesktop/IReaderDesktopExtensions.dart';
import 'Services/Mangayomi/MangayomiExtensions.dart';
import 'Services/Sora/SoraExtensions.dart';
import 'Services/Tsundoku/TsundokuAndroid/TsundokuExtensions.dart';
import 'Services/Tsundoku/TsundokuDesktop/TsundokuDesktopExtensions.dart';
import 'Settings/KvStore.dart';

class ExtensionManager extends GetxController {
  final List<Extension> managers = [];

  final current = <ItemType, Extension>{}.obs;

  final Map<Type, SourceMethods Function(Source)> _factories = {};

  Extension operator [](ItemType type) => current[type]!;

  List<Extension> get _extensionManagers => [
    MangayomiExtensions(),
    SoraExtensions(),
    if (Platform.isAndroid) AniyomiExtensions(),
    if (Platform.isAndroid) CloudStreamExtensions(),
    if (Platform.isAndroid) IReaderExtensions(),
    if (Platform.isAndroid) TsundokuExtensions(),
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
      AniyomiDesktopExtensions(),
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
      CloudStreamDesktopExtensions(),
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
      IReaderDesktopExtensions(),
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
      TsundokuDesktopExtensions(),
  ];

  @override
  void onInit() {
    super.onInit();

    managers.addAll(_extensionManagers);

    for (final ext in managers) {
      _factories[ext.sourceMethodFactories.$1] = ext.sourceMethodFactories.$2;
    }

    for (final type in ItemType.values) {
      current[type] = _resolveManager(type, getVal("${type.name}Manager"));
    }

    _forEachCurrent((extension, type) {
      return extension.initializeInstalled(type);
    });
  }

  Future<void> _forEachCurrent(
    Future<void> Function(Extension extension, ItemType type) action,
  ) async {
    await Future.wait(
      current.entries.map((entry) => action(entry.value, entry.key)),
    );
  }

  void initializeAvailable() {
    _forEachCurrent((extension, type) {
      return extension.initializeAvailable(type);
    });
  }

  void switchManager(ItemType type, String id) {
    final next = _findById(id);

    if (next == null) return;
    if (!next.supports(type)) return;
    if (current[type]! == next) return;

    current[type] = next;

    setVal("${type.name}Manager", id);

    unawaited(next.initializeInstalled(type));
    unawaited(next.initializeAvailable(type));
  }

  Extension _resolveManager(ItemType type, String? id) {
    final saved = _findById(id);

    if (saved != null && saved.supports(type)) {
      return saved;
    }

    return managers.firstWhere((e) => e.supports(type));
  }

  @override
  void dispose() {
    for (final manager in managers) {
      manager.dispose();
    }
    super.dispose();
  }

  T? find<T extends Extension>() {
    for (final manager in managers) {
      if (manager is T) {
        return manager;
      }
    }
    return null;
  }

  T get<T extends Extension>() {
    final result = find<T>();

    if (result == null) {
      throw Exception(
        'Extension manager of type $T not registered\n'
        'Perhaps $T is not supported on ${Platform.operatingSystem}?',
      );
    }

    return result;
  }

  Extension? _findById(String? id) {
    if (id == null) return null;

    for (final manager in managers) {
      if (manager.id == id) {
        return manager;
      }
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

    throw Exception("No SourceMethods registered for ${source.runtimeType}");
  }
}

extension SourceExecution on Source {
  SourceMethods get methods {
    if (this is SourceMethods) {
      return this as SourceMethods;
    }

    return Get.find<ExtensionManager>().createSourceMethods(this);
  }
}
