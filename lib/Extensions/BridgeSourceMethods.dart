import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../Extensions/SourceMethods.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/Source.dart';
import '../../Models/SourcePreference.dart';
import '../../Models/Video.dart';
import 'ExtensionBridge.dart';

abstract class BridgeSourceMethods<T extends Source> extends SourceMethods {
  @override
  final T source;

  final ExtensionBridge bridge;

  BridgeSourceMethods(this.source, this.bridge);

  bool get isAnime => source.itemType?.index == 1;

  Map<String, dynamic> _mediaToJson(DMedia media) => {
    'title': media.title,
    'url': media.url,
    'thumbnail_url': media.cover,
    'description': media.description,
    'author': media.author,
    'artist': media.artist,
    'genre': media.genre,
  };

  Map<String, dynamic> _episodeToJson(DEpisode episode) => {
    'name': episode.name,
    'url': episode.url,
    'date_upload': episode.dateUpload,
    'description': episode.description,
    'episode_number': episode.episodeNumber,
    'scanlator': episode.scanlator,
  };

  @override
  Future<DMedia> getDetail(DMedia media) async {
    final result = await bridge.call<Map<String, dynamic>>('getDetail', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'media': jsonEncode(_mediaToJson(media)),
    });

    return compute(DMedia.fromJson, result);
  }

  @override
  Future<Pages> getPopular(int page) async {
    final result = await bridge.call<Map<String, dynamic>>('getPopular', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'page': page,
    });

    return compute(Pages.fromJson, result);
  }

  @override
  Future<Pages> getLatestUpdates(int page) async {
    final result = await bridge.call<Map<String, dynamic>>('getLatestUpdates', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'page': page,
    });

    return compute(Pages.fromJson, result);
  }

  @override
  Future<Pages> search(String query, int page, List filters) async {
    final result = await bridge.call<Map<String, dynamic>>('search', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'query': query,
      'page': page,
    });

    return compute(Pages.fromJson, result);
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async {
    final result = await bridge.call<List<dynamic>>('getVideoList', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'episode': jsonEncode(_episodeToJson(episode)),
    });

    return compute(parseVideos, result);
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) async {
    final result = await bridge.call<List<dynamic>>('getPageList', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'episode': jsonEncode(_episodeToJson(episode)),
    });

    return compute(parsePageUrls, result);
  }

  @override
  Future<List<SourcePreference>> getPreference() async {
    final result = await bridge.call<List<dynamic>>('getPreference', {
      'sourceId': source.id,
      'isAnime': isAnime,
    });

    return result
        .map((e) => mapToSourcePreference(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) {
    return bridge.call<bool>('saveSourcePreference', {
      'sourceId': source.id,
      'key': pref.key,
      'value': jsonEncode({'value': value}),
    });
  }

  @override
  Future<String?> getNovelContent(DEpisode episode) async {
    final pages = await bridge.call<List<dynamic>>('getNovelContent', {
      'sourceId': source.id,
      'episode': jsonEncode(_episodeToJson(episode)),
    });

    return pages.join('\n');
  }

  static List<Video> parseVideos(List<dynamic> list) =>
      list.map((e) => Video.fromJson(Map<String, dynamic>.from(e))).toList();

  static List<PageUrl> parsePageUrls(List<dynamic> list) =>
      list.map((e) => PageUrl.fromJson(Map<String, dynamic>.from(e))).toList();
}

SourcePreference mapToSourcePreference(Map<String, dynamic> json) {
  final type = json['type'] as String?;
  switch (type) {
    case 'checkbox':
      return SourcePreference(
        key: json['key'],
        type: type,
        checkBoxPreference: CheckBoxPreference(
          title: json['title'],
          summary: json['summary'],
          value: json['value'],
        ),
      );

    case 'switch':
      return SourcePreference(
        key: json['key'],
        type: type,
        switchPreferenceCompat: SwitchPreferenceCompat(
          title: json['title'],
          summary: json['summary'],
          value: json['value'],
        ),
      );

    case 'list':
      final entries = (json['entries'] as List?)
          ?.map((e) => e.toString())
          .toList();
      final entryValues = (json['entryValues'] as List?)
          ?.map((e) => e.toString())
          .toList();
      final valueIndex = entryValues?.indexOf(json['value']?.toString() ?? '');
      return SourcePreference(
        key: json['key'],
        type: type,
        listPreference: ListPreference(
          title: json['title'],
          summary: json['summary'],
          value: json['value']?.toString(),
          entries: entries,
          entryValues: entryValues,
          valueIndex: valueIndex != -1 ? valueIndex : 0,
        ),
      );

    case 'multi_select':
      final entries = (json['entries'] as List?)
          ?.map((e) => e.toString())
          .toList();
      final entryValues = (json['entryValues'] as List?)
          ?.map((e) => e.toString())
          .toList();
      final values =
          (json['value'] as List?)?.map((e) => e.toString()).toList() ?? [];
      return SourcePreference(
        key: json['key'],
        type: type,
        multiSelectListPreference: MultiSelectListPreference(
          title: json['title'],
          summary: json['summary'],
          entries: entries,
          entryValues: entryValues,
          values: values,
        ),
      );

    case 'text':
      return SourcePreference(
        key: json['key'],
        type: type,
        editTextPreference: EditTextPreference(
          title: json['title'],
          summary: json['summary'],
          value: json['value']?.toString(),
        ),
      );

    default:
      return SourcePreference(key: json['key']);
  }
}
