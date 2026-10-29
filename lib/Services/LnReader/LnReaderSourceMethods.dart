import 'dart:async';

import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/SourcePreference.dart';
import '../../Models/Video.dart';
import '../../Network/MClient.dart';
import 'LnReaderWorker.dart';
import 'Models/Source.dart';

/// Runs a single LNReader plugin (`source.sourceCode`) in its own QuickJS
/// runtime inside a background isolate ([LnReaderWorker]) and maps its output onto the bridge's [SourceMethods] surface.
///
/// LNReader is novel-only: [getPageList] / [getVideoList] are stubs and chapter
/// bodies come back from [getNovelContent] as an HTML string.
class LnReaderSourceMethods extends SourceMethods {
  @override
  final LSource source;

  LnReaderSourceMethods(this.source) {
    _live.add(this);
  }

  /// Every live instance, so [LnReaderExtensions.dispose] can free the runtimes.
  static final Set<LnReaderSourceMethods> _live = {};

  static void disposeAll() {
    for (final m in _live.toList()) {
      m.dispose();
    }
  }

  LnReaderWorker? _worker;
  Future<LnReaderWorker>? _starting;

  Future<LnReaderWorker> _ensureWorker() =>
      _starting ??= _spawn().catchError((Object e, StackTrace s) {
        _starting = null;
        Error.throwWithStackTrace(e, s);
      });

  Future<LnReaderWorker> _spawn() async {
    var code = source.sourceCode ?? '';
    if (code.isEmpty && (source.sourceCodeUrl?.isNotEmpty ?? false)) {
      final res = await MClient.init().get(Uri.parse(source.sourceCodeUrl!));
      if (res.statusCode != 200) {
        throw Exception(
          'Failed to fetch plugin from ${source.sourceCodeUrl}: '
          '${res.statusCode}',
        );
      }
      code = res.body;
    }
    if (code.isEmpty) {
      throw Exception('No plugin code available for ${source.name}');
    }
    final worker = await LnReaderWorker.spawn(
      sourceId: source.id ?? source.name ?? 'lnreader',
      code: code,
    );
    _worker = worker;
    return worker;
  }

  Future<Pages> _pages(String op, Map<String, Object?> args) async {
    final worker = await _ensureWorker();
    final json = await worker.pages(op, args);
    return Pages(
      list: [
        for (final m in json['list'] as List)
          DMedia.fromJson(Map<String, dynamic>.from(m as Map)),
      ],
      hasNextPage: json['hasNextPage'] as bool,
    );
  }

  @override
  Future<Pages> getPopular(int page) =>
      _pages('popular', {'page': page, 'latest': false});

  @override
  Future<Pages> getLatestUpdates(int page) =>
      _pages('popular', {'page': page, 'latest': true});

  @override
  Future<Pages> search(String query, int page, List<dynamic> filters) =>
      _pages('search', {'query': query, 'page': page});

  @override
  Future<DMedia> getDetail(DMedia media) async {
    final worker = await _ensureWorker();
    return DMedia.fromJson(await worker.detail(media));
  }

  @override
  Future<String?> getNovelContent(DEpisode episode) async {
    try {
      final worker = await _ensureWorker();
      return await worker.content(episode.url ?? '');
    } catch (e) {
      Logger.log('LNReader parseChapter failed: $e');
      return null;
    }
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) async => const [];

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async => const [];

  @override
  Future<List<SourcePreference>> getPreference() async {
    final worker = await _ensureWorker();
    final raw = await worker.settings();
    if (raw is! Map) return const [];

    final prefs = <SourcePreference>[];
    raw.forEach((key, value) {
      if (value is! Map) return;
      final label = value['label']?.toString() ?? key.toString();
      final type = value['type']?.toString() ?? 'Text';
      final current = value['value'];

      switch (type) {
        case 'Switch':
          prefs.add(
            SourcePreference(
              key: key.toString(),
              type: 'switch',
              switchPreferenceCompat: SwitchPreferenceCompat(
                title: label,
                value: current == true,
              ),
            ),
          );
          break;
        case 'Select':
          final options = (value['options'] as List?) ?? const [];
          prefs.add(
            SourcePreference(
              key: key.toString(),
              type: 'list',
              listPreference: ListPreference(
                title: label,
                value: current?.toString(),
                entries: options
                    .map((o) => (o as Map)['label']?.toString() ?? '')
                    .toList(),
                entryValues: options
                    .map((o) => (o as Map)['value']?.toString() ?? '')
                    .toList(),
              ),
            ),
          );
          break;
        default:
          prefs.add(
            SourcePreference(
              key: key.toString(),
              type: 'text',
              editTextPreference: EditTextPreference(
                title: label,
                value: current?.toString(),
              ),
            ),
          );
      }
    });
    return prefs;
  }

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async {
    final key = pref.key;
    if (key == null) return false;
    try {
      final worker = await _ensureWorker();
      await worker.setPreference(key, value);
      return true;
    } catch (e) {
      Logger.log('LNReader setPreference failed: $e');
      return false;
    }
  }

  void dispose() {
    _live.remove(this);
    final worker = _worker;
    _worker = null;
    _starting = null;
    if (worker != null) unawaited(worker.dispose());
  }
}
