import '../../../Models/Source.dart';

class SSource extends Source {
  final String? sourceCode;
  final String? sourceCodeUrl;

  SSource({
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
    this.sourceCode,
    this.sourceCodeUrl,
  });

  factory SSource.fromJson(Map<String, dynamic> json) {
    final base = Source.fromJson(json);

    return SSource(
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
      sourceCode: json['sourceCode'],
      sourceCodeUrl: json['sourceCodeUrl'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();

    json['sourceCode'] = sourceCode;
    json['sourceCodeUrl'] = sourceCodeUrl;

    return json;
  }

  SSource copyWith({
    String? sourceCode,
    String? sourceCodeUrl,
    String? version,
    String? versionLast,
    bool? hasUpdate,
  }) {
    return SSource(
      id: id,
      name: name,
      baseUrl: baseUrl,
      lang: lang,
      isNsfw: isNsfw,
      iconUrl: iconUrl,
      version: version ?? this.version,
      versionLast: versionLast ?? this.versionLast,
      itemType: itemType,
      repo: repo,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      sourceCode: sourceCode ?? this.sourceCode,
      sourceCodeUrl: sourceCodeUrl ?? this.sourceCodeUrl,
    );
  }

  factory SSource.fromSource(
    Source source, {
    String? sourceCode,
    String? sourceCodeUrl,
  }) {
    return SSource(
      id: source.id,
      name: source.name,
      baseUrl: source.baseUrl,
      lang: source.lang,
      isNsfw: source.isNsfw,
      iconUrl: source.iconUrl,
      version: source.version,
      versionLast: source.versionLast,
      itemType: source.itemType,
      repo: source.repo,
      hasUpdate: source.hasUpdate,
      sourceCode: sourceCode,
      sourceCodeUrl: sourceCodeUrl,
    );
  }
}
