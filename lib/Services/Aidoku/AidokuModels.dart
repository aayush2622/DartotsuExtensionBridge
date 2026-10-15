import 'Postcard.dart';

class AChapter {
  String key;
  String? title;
  double? chapterNumber;
  double? volumeNumber;
  int? dateUploaded;
  List<String>? scanlators;
  String? url;
  String? language;
  String? thumbnail;
  bool locked;

  AChapter({
    required this.key,
    this.title,
    this.chapterNumber,
    this.volumeNumber,
    this.dateUploaded,
    this.scanlators,
    this.url,
    this.language,
    this.thumbnail,
    this.locked = false,
  });

  static AChapter decode(PostcardReader r) {
    return AChapter(
      key: r.readString(),
      title: r.readOption(r.readString),
      chapterNumber: r.readOption(r.readF32),
      volumeNumber: r.readOption(r.readF32),
      dateUploaded: r.readOption(r.readVarI),
      scanlators: r.readOption(() => r.readVec(r.readString)),
      url: r.readOption(r.readString),
      language: r.readOption(r.readString),
      thumbnail: r.readOption(r.readString),
      locked: r.readBool(),
    );
  }

  void encode(PostcardWriter w) {
    w.writeString(key);
    w.writeOption(title, w.writeString);
    w.writeOption(chapterNumber, w.writeF32);
    w.writeOption(volumeNumber, w.writeF32);
    w.writeOption(dateUploaded, w.writeVarI);
    w.writeOption(scanlators, (v) => w.writeVec(v, w.writeString));
    w.writeOption(url, w.writeString);
    w.writeOption(language, w.writeString);
    w.writeOption(thumbnail, w.writeString);
    w.writeBool(locked);
  }
}

class AManga {
  String key;
  String title;
  String? cover;
  List<String>? artists;
  List<String>? authors;
  String? description;
  String? url;
  List<String>? tags;
  int status;
  int contentRating;
  int viewer;
  int updateStrategy;
  int? nextUpdateTime;
  List<AChapter>? chapters;

  AManga({
    required this.key,
    required this.title,
    this.cover,
    this.artists,
    this.authors,
    this.description,
    this.url,
    this.tags,
    this.status = 0,
    this.contentRating = 0,
    this.viewer = 0,
    this.updateStrategy = 0,
    this.nextUpdateTime,
    this.chapters,
  });

  static AManga decode(PostcardReader r) {
    return AManga(
      key: r.readString(),
      title: r.readString(),
      cover: r.readOption(r.readString),
      artists: r.readOption(() => r.readVec(r.readString)),
      authors: r.readOption(() => r.readVec(r.readString)),
      description: r.readOption(r.readString),
      url: r.readOption(r.readString),
      tags: r.readOption(() => r.readVec(r.readString)),
      status: r.readVarU(),
      contentRating: r.readVarU(),
      viewer: r.readVarU(),
      updateStrategy: r.readVarU(),
      nextUpdateTime: r.readOption(r.readVarI),
      chapters: r.readOption(() => r.readVec(() => AChapter.decode(r))),
    );
  }

  void encode(PostcardWriter w) {
    w.writeString(key);
    w.writeString(title);
    w.writeOption(cover, w.writeString);
    w.writeOption(artists, (v) => w.writeVec(v, w.writeString));
    w.writeOption(authors, (v) => w.writeVec(v, w.writeString));
    w.writeOption(description, w.writeString);
    w.writeOption(url, w.writeString);
    w.writeOption(tags, (v) => w.writeVec(v, w.writeString));
    w.writeVarU(status);
    w.writeVarU(contentRating);
    w.writeVarU(viewer);
    w.writeVarU(updateStrategy);
    w.writeOption(nextUpdateTime, w.writeVarI);
    w.writeOption(chapters, (v) => w.writeVec(v, (c) => c.encode(w)));
  }
}

class AMangaPageResult {
  List<AManga> entries;
  bool hasNextPage;

  AMangaPageResult({required this.entries, required this.hasNextPage});

  static AMangaPageResult decode(PostcardReader r) {
    return AMangaPageResult(
      entries: r.readVec(() => AManga.decode(r)),
      hasNextPage: r.readBool(),
    );
  }
}

class APage {
  int contentKind;
  Map<String, String>? context;
  String? contentUrl;
  String? contentText;
  String? thumbnail;
  bool hasDescription;
  String? description;

  APage({
    required this.contentKind,
    this.context,
    this.contentUrl,
    this.contentText,
    this.thumbnail,
    this.hasDescription = false,
    this.description,
  });

  static APage decode(PostcardReader r) {
    final kind = r.readVarU();
    String? contentUrl;
    String? contentText;
    Map<String, String>? context;
    switch (kind) {
      case 0:
        contentUrl = r.readString();
        context = r.readOption(r.readStringMap);
        break;
      case 1:
        contentText = r.readString();
        break;
      case 2:
        r.readVarI();
        break;
      case 3:
        r.readString();
        r.readString();
        break;
      default:
        throw FormatException('Unsupported Aidoku page content kind $kind');
    }
    return APage(
      contentKind: kind,
      context: context,
      contentUrl: contentUrl,
      contentText: contentText,
      thumbnail: r.readOption(r.readString),
      hasDescription: r.readBool(),
      description: r.readOption(r.readString),
    );
  }
}
