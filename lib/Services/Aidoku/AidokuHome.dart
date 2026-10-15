import 'AidokuModels.dart';
import 'Postcard.dart';

class AListing {
  AListing(this.id, this.name);

  final String id;
  final String name;

  static AListing decode(PostcardReader r) {
    final id = r.readString();
    final name = r.readString();
    r.readVarU();
    return AListing(id, name);
  }
}

class AHomeComponent {
  AHomeComponent({
    this.title,
    this.subtitle,
    this.mangas = const [],
    this.listing,
  });

  final String? title;
  final String? subtitle;
  final List<AManga> mangas;
  final AListing? listing;
}

AManga _linkManga(String title, String? image, AManga? manga) =>
    manga ?? AManga(key: '', title: title, cover: image);

List<AHomeComponent> decodeAidokuHome(PostcardReader r) {
  final out = <AHomeComponent>[];
  final count = r.readVarU();

  ({AManga? manga, String title, String? image}) link() {
    final title = r.readString();
    r.readOption(r.readString);
    final image = r.readOption(r.readString);
    AManga? manga;
    final hasValue = r.readOption(() {
      switch (r.readVarU()) {
        case 0:
          r.readString();
        case 1:
          AListing.decode(r);
        case 2:
          manga = AManga.decode(r);
      }
      return true;
    });
    if (hasValue == null) manga = null;
    return (manga: manga, title: title, image: image);
  }

  List<AManga> links() => [
    for (final l in r.readVec(link))
      if (l.manga != null) _linkManga(l.title, l.image, l.manga),
  ];

  for (var i = 0; i < count; i++) {
    final title = r.readOption(r.readString);
    final subtitle = r.readOption(r.readString);
    var mangas = <AManga>[];
    AListing? listing;
    switch (r.readVarU()) {
      case 0:
        r.readVec(link);
        r.readOption(r.readF32);
        r.readOption(r.readVarI);
        r.readOption(r.readVarI);
      case 1:
        mangas = r.readVec(() => AManga.decode(r));
        r.readOption(r.readF32);
      case 2:
        mangas = links();
        listing = r.readOption(() => AListing.decode(r));
      case 3:
        r.readBool();
        r.readOption(r.readVarI);
        mangas = links();
        listing = r.readOption(() => AListing.decode(r));
      case 4:
        r.readOption(r.readVarI);
        mangas = r.readVec(() {
          final manga = AManga.decode(r);
          AChapter.decode(r);
          return manga;
        });
        listing = r.readOption(() => AListing.decode(r));
      default:
        return out;
    }
    out.add(
      AHomeComponent(
        title: title,
        subtitle: subtitle,
        mangas: mangas,
        listing: listing,
      ),
    );
  }
  return out;
}
