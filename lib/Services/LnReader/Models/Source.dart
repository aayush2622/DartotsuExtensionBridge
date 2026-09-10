import '../../../Models/Source.dart';

/// A single LNReader plugin, as listed in a `plugins.min.json` manifest.
///
/// LNReader plugins are self-contained JS modules (one `.js` per source);
/// [sourceCode] holds the downloaded module once installed, [sourceCodeUrl]
/// points at it in the repo. [customCss] is an optional stylesheet a few
/// plugins ship for their reader.
class LSource extends Source {
  String? sourceCode;
  String? sourceCodeUrl;
  String? customCss;
  String? customCssUrl;

  LSource({
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
    this.customCss,
    this.customCssUrl,
  });

  factory LSource.fromJson(Map<String, dynamic> json) {
    final base = Source.fromJson(json);

    return LSource(
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
      customCss: json['customCss'],
      customCssUrl: json['customCssUrl'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['sourceCode'] = sourceCode;
    json['sourceCodeUrl'] = sourceCodeUrl;
    json['customCss'] = customCss;
    json['customCssUrl'] = customCssUrl;
    return json;
  }
}
