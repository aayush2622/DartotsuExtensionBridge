import '../../../../Models/Source.dart';
import '../../../Shared/PackagedSource.dart';

class TdSource extends PackagedSource {
  TdSource({
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
    super.pkgName,
    super.apkName,
    super.apkUrlOverride,
    super.jarUrl,
    super.apkPath,
  });
  factory TdSource.fromJson(Map<String, dynamic> json) {
    return TdSource(
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
      pkgName: json['pkgName'],
      apkName: json['apkName'],
      apkUrlOverride: json['apkUrlOverride'],
      jarUrl: json['jarUrl'],
      apkPath: json['apkPath'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['apkName'] = apkName;
    map['pkgName'] = pkgName;
    map['apkUrlOverride'] = apkUrlOverride;
    map['jarUrl'] = jarUrl;
    map['apkPath'] = apkPath;
    return map;
  }
}
