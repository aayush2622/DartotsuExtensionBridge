import '../../../../Models/Source.dart';

class IdSource extends Source {
  String? apkName;
  String? apkUrl;
  String? apkPath;
  String? pkgName;
  IdSource({
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
    this.apkName,
    this.apkUrl,
    this.apkPath,
    this.pkgName,
  });

  factory IdSource.fromJson(Map<String, dynamic> json) {
    return IdSource(
      id:
          json['id']?.toString().toLowerCase() ??
          json['name']?.toString().toLowerCase() ??
          '',
      name: json['name'],
      baseUrl: json['baseUrl'],
      lang: json['language'] ?? json['lang'],
      iconUrl: json['iconUrl'],
      isNsfw: json['isNsfw'] ?? false,
      version: json['version']?.toString() ?? "1.0.0",
      versionLast: json['versionLast'] ?? "1.0.0",
      repo: json['repo'],
      hasUpdate: json['hasUpdate'] ?? false,
      itemType: ItemType.novel,
      apkName: json['apkName'],
      apkUrl: json['apkUrl'],
      apkPath: json['apkPath'],
      pkgName: json['pkgName'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['apkName'] = apkName;
    map['apkUrl'] = apkUrl;
    map['apkPath'] = apkPath;
    map['pkgName'] = pkgName;
    return map;
  }
}
