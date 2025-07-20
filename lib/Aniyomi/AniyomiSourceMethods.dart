import 'package:dartotsu_extension_bridge/Models/DEpisode.dart';
import 'package:dartotsu_extension_bridge/Models/DMedia.dart';

import 'package:dartotsu_extension_bridge/Models/Pages.dart';

import 'package:dartotsu_extension_bridge/Models/Source.dart';

import 'package:dartotsu_extension_bridge/Models/Video.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../Extensions/SourceMethods.dart';
import '../Models/Page.dart';

class AniyomiSourceMethods implements SourceMethods {
  static const platform = MethodChannel('aniyomiExtensionBridge');

  @override
  late Source source;

  AniyomiSourceMethods(this.source);

  bool get isAnime => source.itemType?.index == 1;

  @override
  Future<DMedia> getDetail(DMedia media) async {
    final result = await platform.invokeMethod('getDetail', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'media': {
        'title': media.title,
        'url': media.url,
        'thumbnail_url': media.cover,
        'description': media.description,
        'author': media.author,
        'artist': media.artist,
        'genre': media.genre,
      },
    });

    return await compute(
      DMedia.fromJson,
      Map<String, dynamic>.from(result as Map),
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
      Map<String, dynamic>.from(result as Map),
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
      Map<String, dynamic>.from(result as Map),
    );
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async {
    final result = await platform.invokeMethod('getVideoList', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'episode': {
        'name': episode.name,
        'url': episode.url,
        'date_upload': episode.dateUpload,
        'description': episode.description,
        'episode_number': episode.episodeNumber,
        'scanlator': episode.scanlator,
      },
    });

    return await compute(parseVideos, List<dynamic>.from(result));
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) {
    throw UnimplementedError();
  }

  @override
  Future<Pages> search(String query, int page, List filters) {
    throw UnimplementedError();
  }

  List<Video> parseVideos(List<dynamic> list) {
    return list
        .map((e) => Video.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
