import 'dart:async';

import 'package:d4rt/d4rt.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';

import '../Models/Source.dart';
import 'DownloadablePlugin.dart';
import 'ExtensionSettings.dart';
import 'SourceMethods.dart';

enum InitState { idle, success, failed }

abstract class Extension {
  String get id;

  String get name;

  bool get supportsAnime => true;

  bool get supportsManga => true;

  bool get supportsNovel => true;

  DownloadablePlugin? get plugin => null;

  (Type, SourceMethods Function(Source)) get sourceMethodFactories;

  Extension() {
    unawaited(_isInstalled());
  }

  Future<void> _isInstalled() async {
    if (plugin == null) return;
    try {
      plugin?.installed.value = await plugin?.isInstalled() ?? true;
    } catch (e, s) {
      Logger.log('Error checking if extension $id is installed: $e\n$s');
      plugin?.installed.value = true;
    }
  }

  final Map<ItemType, Rx<List<Source>>> _installed = {
    ItemType.anime: Rx<List<Source>>([]),
    ItemType.manga: Rx<List<Source>>([]),
    ItemType.novel: Rx<List<Source>>([]),
  };

  final Map<ItemType, Rx<List<Source>>> _available = {
    ItemType.anime: Rx<List<Source>>([]),
    ItemType.manga: Rx<List<Source>>([]),
    ItemType.novel: Rx<List<Source>>([]),
  };

  final Map<ItemType, Rx<List<Source>>> _availableRaw = {
    ItemType.anime: Rx<List<Source>>([]),
    ItemType.manga: Rx<List<Source>>([]),
    ItemType.novel: Rx<List<Source>>([]),
  };

  final Map<ItemType, Rx<List<Repo>>> _repos = {
    ItemType.anime: Rx<List<Repo>>([]),
    ItemType.manga: Rx<List<Repo>>([]),
    ItemType.novel: Rx<List<Repo>>([]),
  };

  @protected
  Future<bool> onInitialize() async => true;

  Completer<void>? _initCompleter;
  InitState _initState = InitState.idle;

  bool get isReady => _initState == InitState.success;

  bool get isFailed => _initState == InitState.failed;

  Future<void> initialize() async {
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();

    try {
      final ok = await onInitialize();
      _initState = ok ? InitState.success : InitState.failed;

      _initCompleter!.complete();
    } catch (e, s) {
      _initState = InitState.failed;
      _initCompleter!.completeError(e, s);
      rethrow;
    }

    return _initCompleter!.future;
  }

  Future<bool> ensureInitialized() async {
    if (_initState == InitState.success) return true;
    if (_initState == InitState.failed) return false;

    await initialize();
    return _initState == InitState.success;
  }

  Future<void> runIfReady(Future<void> Function() fn) async {
    if (!isReady && !await ensureInitialized()) return;
    return fn();
  }

  bool _isInstalledInitialized = false;

  @mustCallSuper
  Future<void> initializeInstalled() async {
    if (!await ensureInitialized()) return;
    if (_isInstalledInitialized) return;

    _isInstalledInitialized = true;

    try {
      if (supportsAnime) unawaited(fetchInstalledAnimeExtensions());
      if (supportsManga) unawaited(fetchInstalledMangaExtensions());
      if (supportsNovel) unawaited(fetchInstalledNovelExtensions());
    } catch (e, s) {
      Logger.log('Error initializing extension $id: $e\n$s');
    }
  }

  bool _isAvailableInitialized = false;

  @mustCallSuper
  Future<void> initializeAvailable() async {
    if (!await ensureInitialized()) return;
    if (_isAvailableInitialized) return;

    _isAvailableInitialized = true;

    try {
      if (supportsAnime) unawaited(fetchAnimeExtensions());
      if (supportsManga) unawaited(fetchMangaExtensions());
      if (supportsNovel) unawaited(fetchNovelExtensions());
    } catch (e, s) {
      Logger.log('Error initializing extension $id: $e\n$s');
    }
  }

  Future<void> addRepo(String repoUrl, ItemType type);

  Future<void> removeRepo(String repoUrl, ItemType type);

  Future<void> installSource(Source source);

  Future<void> uninstallSource(Source source);

  Future<void> updateSource(Source source);

  @mustCallSuper
  Future<void> fetchAnimeExtensions() async {
    if (!isReady && !await ensureInitialized()) return;
  }

  @mustCallSuper
  Future<void> fetchMangaExtensions() async {
    if (!isReady && !await ensureInitialized()) return;
  }

  @mustCallSuper
  Future<void> fetchNovelExtensions() async {
    if (!isReady && !await ensureInitialized()) return;
  }

  @mustCallSuper
  Future<void> fetchInstalledAnimeExtensions() async {
    if (!isReady && !await ensureInitialized()) return;
  }

  @mustCallSuper
  Future<void> fetchInstalledMangaExtensions() async {
    if (!isReady && !await ensureInitialized()) return;
  }

  @mustCallSuper
  Future<void> fetchInstalledNovelExtensions() async {
    if (!isReady && !await ensureInitialized()) return;
  }

  Set<String> get schemes => {};

  void handleSchemes(Uri uri) {}

  Rx<List<Source>> getInstalledRx(ItemType type) => _installed[type]!;

  Rx<List<Source>> getAvailableRx(ItemType type) => _available[type]!;

  Rx<List<Source>> getRawAvailableRx(ItemType type) => _availableRaw[type]!;

  Rx<List<Repo>> getReposRx(ItemType type) => _repos[type]!;

  List<ExtensionSetting> settings(BuildContext context) => [];

  Future<void> setInstalled(ItemType type, List<Source> sources) async {
    getInstalledRx(type).value = sources;
  }

  int compareVersions(String v1, String v2) {
    final a = v1.split('.').map(int.tryParse).toList();
    final b = v2.split('.').map(int.tryParse).toList();

    for (int i = 0; i < a.length || i < b.length; i++) {
      final n1 = i < a.length ? a[i] ?? 0 : 0;
      final n2 = i < b.length ? b[i] ?? 0 : 0;

      if (n1 != n2) return n1.compareTo(n2);
    }

    return 0;
  }
}

class Repo {
  final String url;
  final String? name;
  final String? iconUrl;
  final String? extensions;

  Repo({
    required this.url,
    this.name,
    this.iconUrl,
    this.extensions,
  });

  factory Repo.fromJson(Map<String, dynamic> json) {
    return Repo(
      url: json['url'],
      name: json['name'],
      iconUrl: json['iconUrl'],
      extensions: json['extensions'],
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'name': name,
        'iconUrl': iconUrl,
        'extensions': extensions,
      };
}
