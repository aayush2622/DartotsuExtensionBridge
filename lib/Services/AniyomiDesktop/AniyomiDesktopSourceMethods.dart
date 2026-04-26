import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../Extensions/SourceMethods.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/SourcePreference.dart';
import '../../Models/Video.dart';
import '../Aniyomi/AniyomiSourceMethods.dart';
import '../Aniyomi/Models/Source.dart';
import '../JavaEngine.dart';

class AniyomiSourceMethodsDesktop extends SourceMethods {
  @override
  final ASource source;
  final JavaEngine jni;
  AniyomiSourceMethodsDesktop(this.source, this.jni);

  bool get isAnime => source.itemType?.index == 1;

  @override
  Future<DMedia> getDetail(DMedia media) async {
    final result = await jni.call<Map<String, dynamic>>(
      'getDetail',
      {
        'sourceId': source.id,
        'isAnime': isAnime,
        'media': jsonEncode({
          'title': media.title,
          'url': media.url,
          'thumbnail_url': media.cover,
          'description': media.description,
          'author': media.author,
          'artist': media.artist,
          'genre': media.genre,
        }),
      },
      true,
    );

    return await compute(DMedia.fromJson, result);
  }

  @override
  Future<Pages> getLatestUpdates(int page) async {
    final result = await jni.call<Map<String, dynamic>>(
      'getLatestUpdates',
      {
        'sourceId': source.id,
        'isAnime': isAnime,
        'page': page,
      },
    );

    return await compute(Pages.fromJson, result);
  }

  @override
  Future<Pages> getPopular(int page) async {
    final result = await jni.call<Map<String, dynamic>>(
      'getPopular',
      {
        'sourceId': source.id,
        'isAnime': isAnime,
        'page': page,
      },
    );

    return await compute(Pages.fromJson, result);
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async {
    final result = await jni.call<List<dynamic>>(
      'getVideoList',
      {
        'sourceId': source.id,
        'isAnime': isAnime,
        'episode': jsonEncode(
          {
            'name': episode.name,
            'url': episode.url,
            'date_upload': episode.dateUpload,
            'description': episode.description,
            'episode_number': episode.episodeNumber,
            'scanlator': episode.scanlator,
          },
        ),
      },
    );

    return await compute(parseVideos, result);
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) async {
    final result = await jni.call<List<dynamic>>(
      'getPageList',
      {
        'sourceId': source.id,
        'isAnime': isAnime,
        'episode': jsonEncode(
          {
            'name': episode.name,
            'url': episode.url,
            'date_upload': episode.dateUpload,
            'description': episode.description,
            'episode_number': episode.episodeNumber,
            'scanlator': episode.scanlator,
          },
        ),
      },
    );

    return await compute(parsePageUrls, result);
  }

  @override
  Future<Pages> search(String query, int page, List filters) async {
    final result = await jni.call<Map<String, dynamic>>(
      'search',
      {
        'sourceId': source.id,
        'isAnime': isAnime,
        'query': query,
        'page': page,
      },
      true,
    );

    return await compute(Pages.fromJson, result);
  }

  @override
  Future<List<SourcePreference>> getPreference() async {
    final result = await jni.call<List<dynamic>>(
      'getPreference',
      {
        'sourceId': source.id,
        'isAnime': isAnime,
      },
    );

    if (result.isEmpty) return const [];

    return result
        .map((e) => mapToSourcePreference(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async {
    return await jni.call<bool>(
      'saveSourcePreference',
      {
        'sourceId': source.id,
        'key': pref.key,
        'value': jsonEncode({
          "value": value,
        }),
      },
    );
  }

  List<Video> parseVideos(List<dynamic> list) {
    return list
        .map((e) => Video.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  List<PageUrl> parsePageUrls(List<dynamic> list) {
    return list
        .map((e) => PageUrl.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId) {
    throw UnimplementedError();
  }
}
