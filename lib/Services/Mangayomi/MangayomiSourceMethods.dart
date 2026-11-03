import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../Extensions/SourceMethods.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/SourceFilter.dart' as s;
import '../../Models/SourcePreference.dart' as s;
import '../../Models/Video.dart' as app;
import 'Eval/dart/model/filter.dart';
import 'Eval/dart/model/m_manga.dart';
import 'Eval/dart/model/m_pages.dart';
import 'Eval/dart/model/page.dart' as ev;
import 'Eval/dart/model/source_preference.dart';
import 'Eval/dart/model/video.dart' as ev;
import 'Models/Source.dart';
import 'Util/ChapterRecognition.dart';
import 'Util/extension_preferences_providers.dart';
import 'Util/lib.dart';

class MangayomiSourceMethods extends SourceMethods {
  @override
  final MSource source;

  MangayomiSourceMethods(this.source);

  static void invalidate(String? sourceId) {
    invalidateExtensionService(sourceId);
    if (sourceId != null) knownSources.remove(sourceId);
  }

  static void disposeAll() {
    disposeAllExtensionServices();
    knownSources.clear();
  }

  Future<T> _call<T>(String op, List args) async {
    final id = source.id;
    if (id != null) knownSources[id] = source;
    final service = getExtensionService(source);
    try {
      final Object result = switch (op) {
        'getPopular' => await service.getPopular(args[0] as int),
        'getLatestUpdates' => await service.getLatestUpdates(args[0] as int),
        'search' => await service.search(
          args[0] as String,
          args[1] as int,
          fromJsonFilterValuesToList(args[2] as List),
        ),
        'getDetail' => await service.getDetail(args[0] as String),
        'getPageList' => await service.getPageList(args[0] as String),
        'getVideoList' => await service.getVideoList(args[0] as String),
        'getHtmlContent' => await service.getHtmlContent(
          args[0] as String,
          args[1] as String,
        ),
        'getSourcePreferences' => service.getSourcePreferences(),
        'getFilterList' => service.getFilterList(),
        _ => throw UnsupportedError('Unknown operation: $op'),
      };
      return result as T;
    } finally {
      releaseExtensionService(source, service);
    }
  }

  @override
  Future<DMedia> getDetail(DMedia media) async {
    final data = await _call<MManga>('getDetail', [media.url!]);

    DMedia createMediaData(Map<String, dynamic> args) {
      final media = args['media'] as DMedia;
      final data = args['data'] as MManga;

      final episodes = data.chapters
          ?.where((e) => e.name != null && e.url != null)
          .map(
            (e) => DEpisode(
              name: e.name!,
              url: e.url!,
              episodeNumber: ChapterRecognition.parseChapterNumber(
                media.title ?? '',
                e.name!,
              ).toString(),
              dateUpload: e.dateUpload,
              scanlator: e.scanlator,
            ),
          )
          .toList();
      return DMedia(
        title: media.title,
        url: media.url,
        cover: media.cover,
        description: data.description,
        artist: data.artist,
        author: data.author,
        genre: data.genre,
        episodes: episodes,
      );
    }

    final mediaData = await compute(createMediaData, {
      'media': media,
      'data': data,
    });
    return mediaData;
  }

  @override
  Future<Pages> getLatestUpdates(int page) async {
    final data = await _call<MPages>('getLatestUpdates', [page]);
    return Pages(hasNextPage: data.hasNextPage, list: _mapMediaList(data.list));
  }

  @override
  Future<Pages> getPopular(int page) async {
    final data = await _call<MPages>('getPopular', [page]);
    return Pages(hasNextPage: data.hasNextPage, list: _mapMediaList(data.list));
  }

  @override
  Future<List<s.SourceFilter>> getFilterList() async {
    try {
      final data = await _call<FilterList>('getFilterList', const []);
      return data.filters
          .map(_toGenericFilter)
          .whereType<s.SourceFilter>()
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<Pages> search(String query, int page, List filters) async {
    final mangayomiFilters = filters
        .whereType<Map>()
        .map((e) => s.SourceFilter.fromJson(Map<String, dynamic>.from(e)))
        .map(_toMangayomiFilterJson)
        .toList();
    final data = await _call<MPages>('search', [query, page, mangayomiFilters]);
    return Pages(hasNextPage: data.hasNextPage, list: _mapMediaList(data.list));
  }

  s.SourceFilter? _toGenericFilter(dynamic f) {
    if (f is HeaderFilter) {
      return s.SourceFilter(type: 'header', name: f.name);
    }
    if (f is SeparatorFilter) {
      return s.SourceFilter(type: 'separator', name: '');
    }
    if (f is TextFilter) {
      return s.SourceFilter(type: 'text', name: f.name, textValue: f.state);
    }
    if (f is CheckBoxFilter) {
      return s.SourceFilter(
        type: 'checkbox',
        name: f.name,
        checkBoxValue: f.state,
      );
    }
    if (f is TriStateFilter) {
      return s.SourceFilter(type: 'tri_state', name: f.name, triState: f.state);
    }
    if (f is SelectFilter) {
      return s.SourceFilter(
        type: 'select',
        name: f.name,
        selectIndex: f.state,
        selectOptions: f.values
            .map((v) => v is SelectFilterOption ? v.name : v.toString())
            .toList(),
      );
    }
    if (f is SortFilter) {
      return s.SourceFilter(
        type: 'sort',
        name: f.name,
        sortIndex: f.state.index,
        sortAscending: f.state.ascending,
        sortOptions: f.values
            .map((v) => v is SelectFilterOption ? v.name : v.toString())
            .toList(),
      );
    }
    if (f is GroupFilter) {
      return s.SourceFilter(
        type: 'group',
        name: f.name,
        group: f.state
            .map(_toGenericFilter)
            .whereType<s.SourceFilter>()
            .toList(),
      );
    }
    return null;
  }

  Map<String, dynamic> _toMangayomiFilterJson(s.SourceFilter f) {
    List<Map<String, dynamic>> options(List<String>? entries) =>
        (entries ?? const [])
            .map((e) => {'name': e, 'value': e, 'type_name': 'SelectOption'})
            .toList();

    return switch (f.type) {
      'header' => {'type': '', 'name': f.name, 'type_name': 'HeaderFilter'},
      'separator' => {'type': '', 'type_name': 'SeparatorFilter'},
      'text' => {
        'type': '',
        'name': f.name,
        'state': f.textValue ?? '',
        'type_name': 'TextFilter',
      },
      'checkbox' => {
        'type': '',
        'name': f.name,
        'value': f.name,
        'state': f.checkBoxValue ?? false,
        'type_name': 'CheckBox',
      },
      'tri_state' => {
        'type': '',
        'name': f.name,
        'value': f.name,
        'state': f.triState ?? 0,
        'type_name': 'TriState',
      },
      'select' => {
        'type': '',
        'name': f.name,
        'state': f.selectIndex ?? 0,
        'values': options(f.selectOptions),
        'type_name': 'SelectFilter',
      },
      'sort' => {
        'type': '',
        'name': f.name,
        'state': {
          'index': f.sortIndex ?? 0,
          'ascending': f.sortAscending ?? false,
          'type_name': 'SortState',
        },
        'values': options(f.sortOptions),
        'type_name': 'SortFilter',
      },
      'group' => {
        'type': '',
        'name': f.name,
        'state': (f.group ?? const []).map(_toMangayomiFilterJson).toList(),
        'type_name': 'GroupFilter',
      },
      _ => {'type': '', 'name': f.name, 'type_name': 'HeaderFilter'},
    };
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) async {
    final data = await _call<List<ev.PageUrl>>('getPageList', [episode.url!]);
    return pagesWithHeaders(
      data.map((e) => PageUrl(e.url, headers: e.headers)).toList(),
      baseUrl: source.baseUrl,
      headers: _sourceHeaders(),
    );
  }

  Map<String, String> _sourceHeaders() {
    final raw = source.headers;
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final e in decoded.entries)
          if (e.value != null) '${e.key}': '${e.value}',
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<List<app.Video>> getVideoList(DEpisode episode) async {
    final data = await _call<List<ev.Video>>('getVideoList', [episode.url!]);

    return data.map((e) {
      return app.Video(
        e.quality,
        e.url,
        e.quality,
        headers: e.headers,
        audios: e.audios
            ?.map((a) => app.Track(file: a.file, label: a.label))
            .toList(),
        subtitles: e.subtitles
            ?.map((s) => app.Track(file: s.file, label: s.label))
            .toList(),
      );
    }).toList();
  }

  @override
  Future<String?> getNovelContent(DEpisode episode) async {
    try {
      return await _call<String>('getHtmlContent', [
        episode.name ?? "",
        episode.url ?? "",
      ]);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<s.SourcePreference>> getPreference() async {
    String getType(SourcePreference pref) {
      if (pref.checkBoxPreference != null) {
        return "checkbox";
      } else if (pref.listPreference != null) {
        return "list";
      } else if (pref.multiSelectListPreference != null) {
        return "multi_select";
      } else if (pref.switchPreferenceCompat != null) {
        return "switch";
      } else if (pref.editTextPreference != null) {
        return "text";
      } else {
        return "other";
      }
    }

    try {
      final defaults = await _call<List<SourcePreference>>(
        'getSourcePreferences',
        const [],
      );
      final resolved = defaults
          .map((e) => resolveSourcePreference(e, source))
          .toList();
      return resolved
          .map(
            (p) => s.SourcePreference.fromJson(p.toJson())..type = getType(p),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<bool> setPreference(s.SourcePreference pref, value) async {
    var data = SourcePreference.fromJson(pref.toJson())
      ..sourceId = extractSourceId(source.id!);
    if (data.listPreference != null) {
      data.listPreference?.valueIndex = data.listPreference?.entryValues
          ?.indexOf(value ?? '');
    } else if (data.checkBoxPreference != null) {
      data.checkBoxPreference?.value = value;
    } else if (data.switchPreferenceCompat != null) {
      data.switchPreferenceCompat?.value = value;
    } else if (data.editTextPreference != null) {
      data.editTextPreference?.value = value;
    } else if (data.multiSelectListPreference != null) {
      data.multiSelectListPreference?.values = value;
    }
    setPreferenceSetting(data, source);
    return true;
  }

  List<DMedia> _mapMediaList(List<dynamic> list) {
    return list
        .map(
          (e) => DMedia(
            title: e.name,
            url: e.link,
            cover: e.imageUrl,
            description: e.description,
            artist: e.artist,
          ),
        )
        .toList();
  }
}
