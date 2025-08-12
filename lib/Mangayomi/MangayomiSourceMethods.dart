import 'dart:developer';

import 'package:dartotsu_extension_bridge/Models/DEpisode.dart';

import 'package:dartotsu_extension_bridge/Models/DMedia.dart';

import 'package:dartotsu_extension_bridge/Models/Page.dart';

import 'package:dartotsu_extension_bridge/Models/Pages.dart';

import 'package:dartotsu_extension_bridge/Models/Source.dart';

import 'package:dartotsu_extension_bridge/Models/Video.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../Extensions/SourceMethods.dart';
import 'ChapterRecognition.dart';
import 'Eval/dart/model/m_manga.dart';
import 'MangayomiExtensionManager.dart';
import 'Models/Source.dart';
import 'lib.dart';

class MangayomiSourceMethods implements SourceMethods {
  @override
  Source source;

  MangayomiSourceMethods(this.source);

  T _ensureSource<T>(T Function(MSource mSource) fn) {
    var manager = Get.find<MangayomiExtensionManager>();
    final sources = source.itemType?.index == 0
        ? manager.installedMangaExtensions
        : source.itemType?.index == 1
        ? manager.installedAnimeExtensions
        : manager.installedNovelExtensions;

    final mSource = sources.value.firstWhereOrNull(
      (s) => s.id.toString() == source.id,
    );

    if (mSource == null) throw Exception('Source is not initialized');
    return fn(mSource);
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

  @override
  Future<DMedia> getDetail(DMedia media) async {
    final data = await _ensureSource(
      (mSource) => getExtensionService(mSource).getDetail(media.url!),
    );

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
    final data = await _ensureSource(
      (mSource) => getExtensionService(mSource).getLatestUpdates(page),
    );

    return Pages(hasNextPage: data.hasNextPage, list: _mapMediaList(data.list));
  }

  @override
  Future<Pages> getPopular(int page) async {
    final data = await _ensureSource(
      (mSource) => getExtensionService(mSource).getPopular(page),
    );

    return Pages(hasNextPage: data.hasNextPage, list: _mapMediaList(data.list));
  }

  @override
  Future<Pages> search(String query, int page, List filters) async {
    final data = await _ensureSource(
      (mSource) => getExtensionService(mSource).search(query, page, filters),
    );

    return Pages(hasNextPage: data.hasNextPage, list: _mapMediaList(data.list));
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) async {
    final data = await _ensureSource(
      (mSource) => getExtensionService(mSource).getPageList(episode.url!),
    );

    return data.map((e) => PageUrl(e.url, headers: e.headers)).toList();
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async {
    final data = await _ensureSource(
      (mSource) => getExtensionService(mSource).getVideoList(episode.url!),
    );

    return data.map((e) {
      return Video(
        e.quality,
        e.url,
        e.quality,
        headers: e.headers,
        audios: e.audios
            ?.map((a) => Track(file: a.file, label: a.label))
            .toList(),
        subtitles: e.subtitles
            ?.map((s) => Track(file: s.file, label: s.label))
            .toList(),
      );
    }).toList();
  }

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId) async {
    try {
      final data = await _ensureSource(
        (mSource) => getExtensionService(
          mSource,
        ).getHtmlContent(chapterTitle, chapterId),
      );

      return data;
    } catch (e) {
      log('[BRIDGE]: getNovelContent error: $e');
      return null;
    }
  }
}
