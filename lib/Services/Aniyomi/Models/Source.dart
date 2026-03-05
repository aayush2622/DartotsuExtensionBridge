import '../../../Models/Source.dart';

class ASource extends Source {
  String? apkUrl;
  int? extensionType;

  ASource({
    super.id,
    super.name,
    super.baseUrl,
    super.lang,
    super.isNsfw,
    super.iconUrl,
    super.version,
    super.versionLast,
    super.itemType,
    super.repo,
    super.hasUpdate,
    this.apkUrl,
    this.extensionType,
  });
  factory ASource.fromJson(Map<String, dynamic> json) {
    return ASource(
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
      itemType: ItemType.values[json['itemType'] ?? 0],
      apkUrl: json['apkUrl'],
      extensionType: json['extensionType'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['apkUrl'] = apkUrl;
    map['extensionType'] = extensionType;
    return map;
  }
}
