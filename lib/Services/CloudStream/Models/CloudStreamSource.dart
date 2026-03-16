import '../../../Models/Source.dart';

class CSource extends Source {
  String? internalName;
  String? pluginUrl;

  CSource({
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
    this.internalName,
    this.pluginUrl,
  });

  factory CSource.fromJson(Map<String, dynamic> json) {
    // print('FROM JSONING CS SOURCE => ${json.toString()}');
    return CSource(
      id: json['id']?.toString().toLowerCase() ??
          json['name']?.toString().toLowerCase() ??
          '',
      name: json['name'],
      baseUrl: json['url'],
      lang: json['language'],
      iconUrl: json['iconUrl'],
      isNsfw: json['isNsfw'] ?? false,
      version: json['version']?.toString() ?? "1.0.0",
      versionLast: json['versionLast'] ?? "1.0.0",
      repo: json['repo'],
      hasUpdate: json['hasUpdate'] ?? false,
      itemType: ItemType.anime,
      internalName: json['internalName'] ?? json['name'],
      pluginUrl: json['pluginUrl'] ?? json['plugin'] ?? json['url'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['internalName'] = internalName;
    map['plugin'] = pluginUrl;
    return map;
  }
}
