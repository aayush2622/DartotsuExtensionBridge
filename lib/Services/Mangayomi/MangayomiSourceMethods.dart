import 'package:flutter/foundation.dart';

import '../../Extensions/SourceMethods.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/SourcePreference.dart' as s;
import '../../Models/Video.dart' as app;
import 'Eval/dart/model/m_manga.dart';
import 'Eval/dart/model/m_pages.dart';
import 'Eval/dart/model/page.dart' as ev;
import 'Eval/dart/model/source_preference.dart';
import 'Eval/dart/model/video.dart' as ev;
import 'Models/Source.dart';
import 'Util/ChapterRecognition.dart';
import 'Util/extension_preferences_providers.dart';
import 'Worker/MangayomiWorkerClient.dart';

class MangayomiSourceMethods implements SourceMethods {
  @override
  final MSource source;

  MangayomiSourceMethods(this.source);

  Future<T> _call<T>(String op, List args) =>
      MangayomiWorkerClient.instance.call<T>(source, op, args);

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
  Future<Pages> search(String query, int page, List filters) async {
    final data = await _call<MPages>('search', [query, page, filters]);
    return Pages(hasNextPage: data.hasNextPage, list: _mapMediaList(data.list));
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) async {
    final data = await _call<List<ev.PageUrl>>('getPageList', [episode.url!]);
    return data.map((e) => PageUrl(e.url, headers: e.headers)).toList();
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
