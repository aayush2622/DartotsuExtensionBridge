import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';

import '../Logger.dart';
import '../Models/Source.dart';
import '../Settings/KvStore.dart';
import 'DownloadablePlugin.dart';
import 'ExtensionSettings.dart';
import 'SourceMethods.dart';

enum InitState { idle, success, failed }

/// Runs [operation] and exposes it as a broadcast [Stream] of progress in
/// `[0.0, 1.0]` that closes (after emitting a final `1.0`) on success or
/// errors and closes on failure.
///
/// [operation] starts immediately, before this function returns - it does
/// NOT wait for a listener, so callers that never subscribe (the previous
/// `Future<void>`-returning API was routinely fire-and-forget, e.g.
/// `onPressed: () => repo.installSource(source)`) still get the underlying
/// work done; a listener only opts into progress/completion/error
/// notifications on top of that. A listener that subscribes after progress
/// has already been reported only sees events from that point on -
/// broadcast streams don't replay history.
Stream<double> progressStream(
  Future<void> Function(void Function(double progress) reportProgress)
  operation,
) {
  final controller = StreamController<double>.broadcast();

  scheduleMicrotask(() async {
    try {
      await operation(controller.add);
      controller.add(1.0);
    } catch (e, s) {
      controller.addError(e, s);
    } finally {
      await controller.close();
    }
  });

  return controller.stream;
}

class ExtensionState {
  final installed = Rx<List<Source>>([]);
  final available = Rx<List<Source>>([]);
  final rawAvailable = Rx<List<Source>>([]);
  final repos = Rx<List<Repo>>([]);
  final activeRepo = Rxn<Repo>();
  final loadingAvailable = false.obs;
  final loadingInstalled = false.obs;

  /// Per-source install/update download progress in [0.0, 1.0], keyed by
  /// [Source.id]. A backend that can report byte-level progress updates
  /// this while installSource()/updateSource() run and removes the entry
  /// when done (success or failure); a backend that can't (e.g. the
  /// desktop JVM-sidecar backends, whose actual download happens on the
  /// Kotlin side) just never populates it for its sources. UI should treat
  /// "no entry" as not-installing and "entry present" as installing,
  /// independent of whether the value itself is meaningful yet.
  final installProgress = <String, double>{}.obs;

  /// Set while addRepo() is fetching a repo big enough that a bare spinner
  /// isn't enough feedback (e.g. Kotatsu's shared parsers jar can be
  /// several MB). [repoLoadProgress] is null while the transfer size isn't
  /// known yet (or for a backend that doesn't report it), 0.0-1.0 once it
  /// is.
  final loadingRepo = false.obs;
  final repoLoadProgress = Rxn<double>();

  final selectedLanguages = <String>{}.obs;

  bool installedInitialized = false;
  bool availableInitialized = false;
}

abstract class Extension {
  String get id;

  String get name;

  String get icon;

  bool get supportsAnime => true;

  bool get supportsManga => true;

  bool get supportsNovel => true;

  DownloadablePlugin? get plugin => null;

  (Type, SourceMethods Function(Source)) get sourceMethodFactories;

  Extension() {
    unawaited(_isInstalled());
    unawaited(_checkAvailableInRepo());
  }
  Future<void> _checkAvailableInRepo() async {
    try {
      if (plugin == null) return;
      await plugin!.checkAvailability();
    } catch (e, s) {
      Logger.log('Error checking repo availability for extension $id: $e\n$s');
      plugin?.availableInRepo.value = false;
    }
  }

  Future<void> _isInstalled() async {
    try {
      if (plugin == null) return;
      plugin!.installed.value = await plugin!.isInstalled();
    } catch (e, s) {
      Logger.log('Error checking if extension $id is installed: $e\n$s');
      plugin?.installed.value = false;
    }
  }

  @protected
  Future<bool> onInitialize() async => true;

  Completer<void>? _initCompleter;
  InitState _initState = InitState.idle;

  bool get isReady => _initState == InitState.success;

  bool get isFailed => _initState == InitState.failed;

  Future<void> initialize() async {
    if (_initCompleter != null) return _initCompleter!.future;

    final completer = _initCompleter = Completer<void>();

    try {
      final ok = await onInitialize();
      _initState = ok ? InitState.success : InitState.failed;

      // A failed init must not pin _initCompleter forever - ensureInitialized
      // short-circuits on InitState.failed without ever calling initialize()
      // again, so leaving the completer set here would permanently disable
      // this backend after a single transient failure (a cold-start network
      // blip, a sidecar/JVM handshake miss, ...) with no way to retry short
      // of restarting the app. Clearing it lets the next ensureInitialized()
      // call attempt onInitialize() again.
      if (!ok) _initCompleter = null;

      completer.complete();
    } catch (e, s) {
      _initState = InitState.failed;
      _initCompleter = null;
      completer.completeError(e, s);
      rethrow;
    }

    return completer.future;
  }

  final _states = <ItemType, ExtensionState>{};

  ExtensionState state(ItemType type) =>
      _states.putIfAbsent(type, ExtensionState.new);

  ExtensionState get anime => state(ItemType.anime);

  ExtensionState get manga => state(ItemType.manga);

  ExtensionState get novel => state(ItemType.novel);
  void dispose() async {}

  Future<bool> ensureInitialized() async {
    if (_initState == InitState.success) return true;

    try {
      await initialize();
    } catch (_) {
      // initialize() already recorded the failure in _initState (and
      // completed its own completer with the error for direct initialize()
      // callers) - ensureInitialized()'s contract is a bool, never a thrown
      // exception, and a failure here must still leave _initCompleter
      // cleared so the *next* call can retry rather than getting stuck.
    }

    return _initState == InitState.success;
  }

  Future<void> runIfReady(Future<void> Function() fn) async {
    if (!isReady && !await ensureInitialized()) return;
    return fn();
  }

  @mustCallSuper
  Future<void> initializeInstalled(ItemType type) async {
    if (!await ensureInitialized()) return;

    final s = state(type);

    if (s.installedInitialized) return;
    s.installedInitialized = true;

    try {
      switch (type) {
        case ItemType.anime:
          if (supportsAnime) {
            unawaited(fetchInstalledAnimeExtensions());
          }
          break;

        case ItemType.manga:
          if (supportsManga) {
            unawaited(fetchInstalledMangaExtensions());
          }
          break;

        case ItemType.novel:
          if (supportsNovel) {
            unawaited(fetchInstalledNovelExtensions());
          }
          break;
      }
      loadSelectedLanguages(type);
    } catch (e, s) {
      Logger.log('Error initializing extension $id: $e\n$s');
    }
  }

  @mustCallSuper
  Future<void> initializeAvailable(ItemType type) async {
    if (!await ensureInitialized()) return;

    final s = state(type);

    if (s.availableInitialized) return;
    s.availableInitialized = true;

    try {
      switch (type) {
        case ItemType.anime:
          if (supportsAnime) {
            unawaited(fetchAnimeExtensions());
          }
          break;

        case ItemType.manga:
          if (supportsManga) {
            unawaited(fetchMangaExtensions());
          }
          break;

        case ItemType.novel:
          if (supportsNovel) {
            unawaited(fetchNovelExtensions());
          }
          break;
      }
    } catch (e, s) {
      Logger.log(
        'Error initializing available extensions for $id ($type): $e\n$s',
      );
    }
  }

  /// Progress in `[0.0, 1.0]`. See [progressStream] for the exact contract
  /// (starts eagerly, broadcast, closes on completion/error).
  Stream<double> installSource(Source source);

  Future<void> uninstallSource(Source source);

  /// Progress in `[0.0, 1.0]`. See [progressStream].
  Stream<double> updateSource(Source source);

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

  List<ExtensionSetting> settings(BuildContext context) => [];

  Future<void> setInstalled(ItemType type, List<Source> sources) async {
    state(type).installed.value = sources;
  }

  Future<List<Source>> fetchExtensions(ItemType type) async {
    var s = state(type);
    s.loadingAvailable.value = true;
    s.available.value = [];
    final repos = loadRepos(type);
    s.repos.value = repos;

    if (repos.isEmpty) {
      s.rawAvailable.value = const [];
      s.loadingAvailable.value = false;
      return const [];
    }

    final active = loadActiveRepo(type) ?? repos.first;
    s.activeRepo.value = active;
    saveActiveRepo(type, active);

    final all = await fetchRepo(active, type);

    final installed = s.installed.value;
    final installedIds = installed.map((e) => e.id).toSet();

    detectUpdates(all, type);

    s.rawAvailable.value = List.unmodifiable(all);
    s.loadingAvailable.value = false;
    return List.unmodifiable(all.where((s) => !installedIds.contains(s.id)));
  }

  List<String> getLanguages(ItemType type) {
    final s = state(type);

    return {
      ...s.installed.value
          .map((e) => e.lang?.toLowerCase())
          .whereType<String>(),
      ...s.rawAvailable.value
          .map((e) => e.lang?.toLowerCase())
          .whereType<String>(),
    }.toList()..sort();
  }

  String _languageKey(ItemType type) => '$id${type.name}Languages';

  Set<String> loadSelectedLanguages(ItemType type) {
    final languages = (getVal<List<String>>(_languageKey(type)) ?? const [])
        .map((e) => e.toLowerCase())
        .toSet();

    state(type).selectedLanguages
      ..clear()
      ..addAll(languages);

    return languages;
  }

  void saveSelectedLanguages(ItemType type, Set<String> languages) {
    state(type).selectedLanguages
      ..clear()
      ..addAll(languages);

    setVal(_languageKey(type), languages.toList(growable: false));
  }

  void detectUpdates(List<Source> available, ItemType type);

  Future<List<Source>> fetchRepo(Repo repo, ItemType type);

  Future<void> updateRepoExtensionCount(
    Repo repo,
    ItemType type,
    int count,
  ) async {
    repo.extensions = count.toString();

    final repos = loadRepos(type);
    final index = repos.indexWhere((r) => r.url == repo.url);

    if (index != -1) {
      repos[index] = repo;
      saveRepos(repos, type);
      state(type).repos.value = List.unmodifiable(repos);
    }
  }

  String repoNameFromUrl(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    return segments.isNotEmpty ? segments.first : uri.host;
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

  List<Repo> loadRepos(ItemType type) {
    final encoded = getVal<List<String>>('$id${type.name}Repos');
    if (encoded == null || encoded.isEmpty) return const [];

    final repos = encoded.map((e) => Repo.fromJson(jsonDecode(e)));

    return {for (final r in repos) r.url: r}.values.toList(growable: false);
  }

  void saveRepos(List<Repo> repos, ItemType type) {
    final key = '$id${type.name}Repos';

    final unique = {for (final r in repos) r.url: r}.values;

    setVal(
      key,
      unique.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }

  /// Progress in `[0.0, 1.0]`. See [progressStream].
  Stream<double> addRepo(String repoUrl, ItemType type);

  Future<void> removeRepo(String repoUrl, ItemType type) async {
    try {
      final previousActive = loadActiveRepo(type);

      final repos = loadRepos(
        type,
      ).where((r) => r.url != repoUrl).toList(growable: false);

      saveRepos(repos, type);
      state(type).repos.value = List.unmodifiable(repos);

      if (previousActive?.url == repoUrl) {
        if (repos.isNotEmpty) {
          saveActiveRepo(type, repos.first);
          state(type).activeRepo.value = repos.first;
        } else {
          setVal("$id${type.name}ActiveRepo", null);
          state(type).activeRepo.value = null;
        }

        await fetchExtension(type);
      }
    } catch (e, s) {
      Logger.log("Failed to remove repo $repoUrl: $e\n$s");
    }
  }

  Repo? loadActiveRepo(ItemType type) {
    final url = getVal<String>("$id${type.name}ActiveRepo");
    if (url == null) return null;

    final repos = loadRepos(type);
    return repos.where((e) => e.url == url).firstOrNull;
  }

  void saveActiveRepo(ItemType type, Repo repo) async {
    final key = "$id${type.name}ActiveRepo";

    setVal(key, repo.url);
  }

  Future<void> selectRepo(Repo repo, ItemType type) async {
    saveActiveRepo(type, repo);
    state(type).activeRepo.value = repo;
    await fetchExtension(type);
  }

  bool supports(ItemType type) => switch (type) {
    ItemType.anime => supportsAnime,
    ItemType.manga => supportsManga,
    ItemType.novel => supportsNovel,
  };
  Future<void> fetchExtension(ItemType type) => switch (type) {
    ItemType.anime => fetchAnimeExtensions(),
    ItemType.manga => fetchMangaExtensions(),
    ItemType.novel => fetchNovelExtensions(),
  };

  Future<void> fetchInstalledExtensions(ItemType type) => switch (type) {
    ItemType.anime => fetchInstalledAnimeExtensions(),
    ItemType.manga => fetchInstalledMangaExtensions(),
    ItemType.novel => fetchInstalledNovelExtensions(),
  };
}

class Repo {
  final String url;
  final String? name;
  final String? iconUrl;
  String? extensions;

  Repo({required this.url, this.name, this.iconUrl, this.extensions});

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
