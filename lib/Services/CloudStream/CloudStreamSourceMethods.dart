import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../dartotsu_extension_bridge.dart';
import 'Models/CloudStreamSource.dart';

class CloudStreamSourceMethods extends SourceMethods {
  @override
  final CSource source;

  CloudStreamSourceMethods(Source source) : source = source as CSource;

  static const platform = MethodChannel('cloudStreamExtensionBridge');

  bool get isAnime => source.itemType?.index == 1;
  @override
  Future<DMedia> getDetail(DMedia media) async {
    final result = await platform.invokeMethod('getDetail', {
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
    });

    return await compute(
      DMedia.fromJson,
      Map<String, dynamic>.from(jsonDecode(result)),
    );
  }

  @override
  Future<Pages> getLatestUpdates(int page) async {
    final result = await platform.invokeMethod('getLatestUpdates', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'page': page,
    });

    return await compute(
      Pages.fromJson,
      Map<String, dynamic>.from(jsonDecode(result)),
    );
  }

  @override
  Future<Pages> getPopular(int page) async {
    final result = await platform.invokeMethod('getPopular', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'page': page,
    });

    return await compute(
      Pages.fromJson,
      Map<String, dynamic>.from(jsonDecode(result)),
    );
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async {
    final result = await platform.invokeMethod('getVideoList', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'episode': jsonEncode({
        'name': episode.name,
        'url': episode.url,
        'date_upload': episode.dateUpload,
        'description': episode.description,
        'episode_number': episode.episodeNumber,
        'scanlator': episode.scanlator,
      }),
    });

    return await compute(parseVideos, List<dynamic>.from(jsonDecode(result)));
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) {
    throw UnimplementedError();
  }

  @override
  Future<Pages> search(String query, int page, List filters) async {
    final result = await platform.invokeMethod('search', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'query': query,
      'page': page,
    });

    return await compute(
      Pages.fromJson,
      Map<String, dynamic>.from(jsonDecode(result)),
    );
  }

  List<Video> parseVideos(List<dynamic> list) {
    return list
        .map((e) => Video.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId) {
    throw UnimplementedError();
  }

  @override
  Future<List<SourcePreference>> getPreference() async {
    return [];
  }

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async {
    return false;
  }
}
