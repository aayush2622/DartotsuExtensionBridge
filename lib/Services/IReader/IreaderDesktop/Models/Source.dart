import '../../../../Models/Source.dart';
import '../../../Shared/PackagedSource.dart';

class IdSource extends PackagedSource {
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
    super.apkName,
    super.apkUrlOverride,
    super.jarUrl,
    super.apkPath,
    super.pkgName,
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
      // Tolerate a legacy stored `apkUrl` by treating it as the override.
      apkUrlOverride: json['apkUrlOverride'] ?? json['apkUrl'],
      jarUrl: json['jarUrl'],
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
    map['apkUrlOverride'] = apkUrlOverride;
    map['jarUrl'] = jarUrl;
    return map;
  }
}
