import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import 'Extensions/Extensions.dart';
import 'Extensions/SourceMethods.dart';
import 'Logger.dart';
import 'Models/Source.dart';
import 'Services/Aniyomi/AniyomiAndroid/AniyomiExtensions.dart';
import 'Services/Aniyomi/AniyomiDesktop/AniyomiDesktopExtensions.dart';
import 'Services/CloudStream/CloudStreamAndroid/CloudStreamExtensions.dart';
import 'Services/CloudStream/CloudStreamDesktop/CloudStreamDesktopExtensions.dart';
import 'Services/IReader/IreaderAndroid/IReaderExtensions.dart';
import 'Services/IReader/IreaderDesktop/IReaderDesktopExtensions.dart';
import 'Services/Kotatsu/KotatsuAndroid/KotatsuExtensions.dart';
import 'Services/Kotatsu/KotatsuDesktop/KotatsuDesktopExtensions.dart';
import 'Services/Legado/LegadoExtensions.dart';
import 'Services/LnReader/LnReaderExtensions.dart';
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

  /// Platforms that drive the desktop backend JARs through a JVM: a `java`
  /// subprocess on real desktops, an embedded OpenJDK Zero VM on iOS.
  static bool get _jvmBackends =>
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS ||
      Platform.isIOS;

  /// Each entry is a factory, not a constructed instance: a backend whose
  /// constructor throws (missing native lib, bad platform assumption, ...)
  /// must not take every other backend down with it - see [_tryCreate].
  List<Extension Function()> get _extensionFactories => [
    MangayomiExtensions.new,
    SoraExtensions.new,
    LnReaderExtensions.new,
    LegadoExtensions.new,
    if (Platform.isAndroid) AniyomiExtensions.new,
    if (Platform.isAndroid) CloudStreamExtensions.new,
    if (Platform.isAndroid) IReaderExtensions.new,
    if (Platform.isAndroid) TsundokuExtensions.new,
    if (Platform.isAndroid) KotatsuExtensions.new,
    if (_jvmBackends) AniyomiDesktopExtensions.new,
    if (_jvmBackends) CloudStreamDesktopExtensions.new,
    if (_jvmBackends) IReaderDesktopExtensions.new,
    if (_jvmBackends) TsundokuDesktopExtensions.new,
    if (_jvmBackends) KotatsuDesktopExtensions.new,
  ];

  List<Extension> get _extensionManagers => [
    for (final create in _extensionFactories) ?_tryCreate(create),
  ];

  Extension? _tryCreate(Extension Function() create) {
    try {
      return create();
    } catch (e, s) {
      Logger.log('Failed to construct an extension manager: $e\n$s');
      return null;
    }
  }

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

    // Every backend registered today defaults to supporting all three
    // ItemTypes, so this isn't reachable yet - but onInit() calls this for
    // every ItemType.values entry, and a future type-restricted backend
    // combined with a platform that excludes every other candidate would
    // otherwise crash GetX bootstrap with an opaque "Bad state: No element".
    return managers.firstWhere(
      (e) => e.supports(type),
      orElse: () => throw StateError(
        'No registered Extension manager supports $type on '
        '${Platform.operatingSystem}',
      ),
    );
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

    if (factory == null) {
      throw Exception("No SourceMethods registered for ${source.runtimeType}");
    }

    return factory(source);
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
