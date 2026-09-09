import 'package:dartotsu_extension_bridge/Models/DEpisode.dart';
import 'package:dartotsu_extension_bridge/Models/DMedia.dart';
import 'package:dartotsu_extension_bridge/Models/Pages.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Models/Video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ItemType', () {
    // Source.toJson persists itemType as its enum index and
    // BridgeSourceMethods.isAnime compares against ItemType.anime; both depend
    // on this exact order.
    test('index order is manga, anime, novel', () {
      expect(ItemType.manga.index, 0);
      expect(ItemType.anime.index, 1);
      expect(ItemType.novel.index, 2);
      expect(ItemType.values, [ItemType.manga, ItemType.anime, ItemType.novel]);
    });

    test('toString is the capitalised label', () {
      expect(ItemType.manga.toString(), 'Manga');
      expect(ItemType.anime.toString(), 'Anime');
      expect(ItemType.novel.toString(), 'Novel');
    });
  });

  group('Source', () {
    test('JSON round-trip preserves itemType and coerces id to String', () {
      final source = Source(
        id: '42',
        name: 'Example',
        baseUrl: 'https://example.com',
        lang: 'en',
        itemType: ItemType.anime,
        version: '1.2.3',
      );

      final decoded = Source.fromJson(source.toJson());

      expect(decoded.id, '42');
      expect(decoded.name, 'Example');
      expect(decoded.baseUrl, 'https://example.com');
      expect(decoded.lang, 'en');
      expect(decoded.itemType, ItemType.anime);
      expect(decoded.version, '1.2.3');
    });

    test('fromJson coerces a numeric id and defaults a missing itemType', () {
      final decoded = Source.fromJson({'id': 7, 'name': 'N'});

      expect(decoded.id, '7');
      expect(decoded.itemType, ItemType.manga); // index 0 fallback
      expect(decoded.hasUpdate, false);
    });
  });

  group('DEpisode.fromJson', () {
    test('reads snake_case episode_number and normalises whole numbers', () {
      final ep = DEpisode.fromJson({'name': 'Ep 5', 'episode_number': '5.0'});
      expect(ep.episodeNumber, '5');
      expect(ep.name, 'Ep 5');
    });

    test('keeps fractional episode numbers', () {
      final ep = DEpisode.fromJson({'episodeNumber': 12.5});
      expect(ep.episodeNumber, '12.5');
    });

    test('non-numeric episode number becomes empty string', () {
      final ep = DEpisode.fromJson({'name': 'Special'});
      expect(ep.episodeNumber, '');
    });

    test('falls back from dateUpload to date_upload', () {
      final ep = DEpisode.fromJson({
        'episode_number': '1',
        'date_upload': '1700000000000',
      });
      expect(ep.dateUpload, '1700000000000');
    });
  });

  group('DMedia / Pages', () {
    test('Pages.fromJson parses nested media and defaults hasNextPage', () {
      final pages = Pages.fromJson({
        'list': [
          {
            'title': 'A',
            'url': '/a',
            'genre': ['action', 'drama'],
            'episodes': [
              {'url': '/a/1', 'name': 'One', 'episode_number': '1'},
            ],
          },
        ],
      });

      expect(pages.hasNextPage, false);
      expect(pages.list, hasLength(1));
      expect(pages.list.single.title, 'A');
      expect(pages.list.single.genre, ['action', 'drama']);
      expect(pages.list.single.episodes, hasLength(1));
      expect(pages.list.single.episodes!.single.episodeNumber, '1');
    });

    test('DMedia.fromJson tolerates a missing genre list', () {
      final media = DMedia.fromJson({'title': 'B', 'url': '/b'});
      expect(media.genre, isEmpty);
      expect(media.episodes, isEmpty);
    });
  });

  group('Video.fromJson', () {
    test('trims fields and defaults subtitle/audio lists', () {
      final video = Video.fromJson({
        'title': '  1080p  ',
        'url': '  https://cdn/v.m3u8 ',
        'quality': ' 1080p ',
      });

      expect(video.title, '1080p');
      expect(video.url, 'https://cdn/v.m3u8');
      expect(video.quality, '1080p');
      expect(video.subtitles, isEmpty);
      expect(video.audios, isEmpty);
    });

    test('parses subtitle tracks', () {
      final video = Video.fromJson({
        'title': 't',
        'url': 'u',
        'quality': 'q',
        'subtitles': [
          {'file': ' https://s/en.vtt ', 'label': ' English '},
        ],
      });

      expect(video.subtitles, hasLength(1));
      expect(video.subtitles!.single.file, 'https://s/en.vtt');
      expect(video.subtitles!.single.label, 'English');
    });
  });
}
