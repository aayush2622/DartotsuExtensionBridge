import '../Mangayomi/Models/Source.dart';

class Source {
  String? id;

  String? name;

  String? baseUrl;

  String? lang;

  bool? isNsfw;

  String? iconUrl;

  String? version;

  String? versionLast;

  ItemType? itemType;

  bool? isObsolete;

  MSource? mSource;

  Source({
    this.id = '',
    this.name = '',
    this.baseUrl = '',
    this.lang = '',
    this.iconUrl = '',
    this.isNsfw = false,
    this.version = "0.0.1",
    this.versionLast = "0.0.1",
    this.itemType = ItemType.manga,
    this.isObsolete = false,
    this.mSource,
  });

  Source.fromJson(Map<String, dynamic> json) {
    baseUrl = json['baseUrl'];
    iconUrl = json['iconUrl'];
    id = json['id'];
    itemType = ItemType.values[json['itemType'] ?? 0];
    isNsfw = json['isNsfw'];
    lang = json['lang'];
    name = json['name'];
    version = json['version'];
    versionLast = json['versionLast'];
    isObsolete = json['isObsolete'];
    mSource = json['mSource'] != null
        ? MSource.fromJson(json['mSource'])
        : null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'lang': lang,
    'iconUrl': iconUrl,
    'isNsfw': isNsfw,
    'version': version,
    'versionLast': versionLast,
    'itemType': itemType?.index ?? 0,
    'isObsolete': isObsolete,
    'mSource': mSource?.toJson(),
  };
}

enum ItemType { manga, anime, novel }
