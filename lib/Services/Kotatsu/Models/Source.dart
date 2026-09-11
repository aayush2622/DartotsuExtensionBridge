import '../../../Models/Source.dart';

/// A manga source read out of the shared Kotatsu parsers jar. Unlike the
/// APK-per-source Android backends, Kotatsu ships every parser in one jar;
/// [jarName] / [pkgName] identify which parser class within it this is.
class KotatsuSource extends Source {
  String? jarName;
  String? pkgName;

  KotatsuSource({
    super.id,
    super.name,
    super.baseUrl,
    super.lang,
    super.isNsfw,
    super.iconUrl,
    super.version,
    super.versionLast,
    super.itemType = ItemType.manga,
    super.repo,
    super.hasUpdate,
    this.jarName,
    this.pkgName,
  });

  factory KotatsuSource.fromJson(Map<String, dynamic> json) {
    return KotatsuSource(
      id: json['id']?.toString(),
      name: json['name'],
      baseUrl: json['baseUrl'],
      lang: json['lang'],
      iconUrl: json['iconUrl'],
      isNsfw: json['isNsfw'],
      version: json['version'],
      versionLast: json['versionLast'],
      repo: json['repo'],
      hasUpdate: json['hasUpdate'] ?? false,
      itemType: ItemType.manga,
      jarName: json['jarName'],
      pkgName: json['pkgName'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['jarName'] = jarName;
    map['pkgName'] = pkgName;
    return map;
  }
}
