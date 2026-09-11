import '../../../../Models/Source.dart';

/// Desktop counterpart of [KotatsuSource]. Kept as a separate class — same
/// convention as CSource/CdSource, TSource/TdSource, IdSource — even though
/// the fields are currently identical, since the two platforms hit different
/// native `ExtensionApi` implementations that could diverge independently.
class KotatsuDesktopSource extends Source {
  String? jarName;
  String? pkgName;

  KotatsuDesktopSource({
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

  factory KotatsuDesktopSource.fromJson(Map<String, dynamic> json) {
    return KotatsuDesktopSource(
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
