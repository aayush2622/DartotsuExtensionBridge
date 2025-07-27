import 'package:get/get.dart';

import '../Aniyomi/AniyomiSourceMethods.dart';
import '../ExtensionManager.dart';
import '../Extensions/SourceMethods.dart';
import '../Mangayomi/MangayomiExtensions.dart';
import '../Mangayomi/MangayomiSourceMethods.dart';

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

  String? repo;

  bool? hasUpdate;

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
    this.repo,
    this.hasUpdate = false,
  });

  Source.fromJson(Map<String, dynamic> json) {
    baseUrl = json['baseUrl'];
    iconUrl = json['iconUrl'];
    id = json['id'].toString();
    itemType = ItemType.values[json['itemType'] ?? 0];
    isNsfw = json['isNsfw'];
    lang = json['lang'];
    name = json['name'];
    version = json['version'];
    versionLast = json['versionLast'];
    isObsolete = json['isObsolete'];
    repo = json['repo'];
    hasUpdate = json['hasUpdate'] ?? false;
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
    'repo': repo,
    'hasUpdate': hasUpdate,
  };
}

extension SMethods on Source {
  SourceMethods get methods {
    final manager = Get.find<ExtensionManager>().currentManager;
    return manager is MangayomiExtensions
        ? MangayomiSourceMethods(this)
        : AniyomiSourceMethods(this);
  }
}

enum ItemType {
  manga,
  anime,
  novel;

  @override
  String toString() {
    switch (this) {
      case ItemType.manga:
        return 'Manga';
      case ItemType.anime:
        return 'Anime';
      case ItemType.novel:
        return 'Novel';
    }
  }
}
