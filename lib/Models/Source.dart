import 'package:dartotsu_extension_bridge/Aniyomi/AniyomiExtensions.dart';
import 'package:dartotsu_extension_bridge/ExtensionManager.dart'
    show ExtensionType, aniyomi;

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

  String? apkUrl;

  ExtensionType? extensionType;

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
    this.extensionType = ExtensionType.aniyomi,
    this.apkUrl = '',
  });

  Source.fromJson(Map<String, dynamic> json, ExtensionType type) {
    final appUrl = type == ExtensionType.aniyomi
        ? getAnimeApkUrl(json['iconUrl'], json['apkName'])
        : '';
    baseUrl = json['baseUrl'];
    iconUrl = json['iconUrl'];
    apkUrl = appUrl;
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
    extensionType = type;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apkUrl': apkUrl,
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

String getAnimeApkUrl(String iconUrl, String apkName) {
  if (iconUrl.isEmpty || apkName.isEmpty) return "";

  final baseUrl = iconUrl.replaceFirst('icon/', 'apk/');
  final lastSlash = baseUrl.lastIndexOf('/');
  if (lastSlash == -1) return "";

  final cleanedUrl = baseUrl.substring(0, lastSlash);
  return '$cleanedUrl/$apkName';
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
