import '../../../Models/Source.dart';

class AidokuSource extends Source {
  String? downloadUrl;
  List<String> languages;
  int contentRating;
  String? minAppVersion;
  String? wasmBytesBase64;
  Map<String, String>? defaults;

  AidokuSource({
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
    this.downloadUrl,
    this.languages = const [],
    this.contentRating = 0,
    this.minAppVersion,
    this.wasmBytesBase64,
    this.defaults,
  });

  factory AidokuSource.fromJson(Map<String, dynamic> json) {
    final base = Source.fromJson(json);

    return AidokuSource(
      id: base.id,
      name: base.name,
      baseUrl: base.baseUrl,
      lang: base.lang,
      isNsfw: base.isNsfw,
      iconUrl: base.iconUrl,
      version: base.version,
      versionLast: base.versionLast,
      itemType: base.itemType,
      repo: base.repo,
      hasUpdate: base.hasUpdate,
      downloadUrl: json['downloadUrl'],
      languages:
          (json['languages'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      contentRating: json['contentRating'] ?? 0,
      minAppVersion: json['minAppVersion'],
      wasmBytesBase64: json['wasmBytesBase64'],
      defaults: (json['defaults'] as Map?)?.map((k, v) => MapEntry('$k', '$v')),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['downloadUrl'] = downloadUrl;
    json['languages'] = languages;
    json['contentRating'] = contentRating;
    json['minAppVersion'] = minAppVersion;
    json['wasmBytesBase64'] = wasmBytesBase64;
    json['defaults'] = defaults;
    return json;
  }
}
