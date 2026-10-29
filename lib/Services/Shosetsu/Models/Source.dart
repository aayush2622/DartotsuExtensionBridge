import '../../../Models/Source.dart';

/// A single Shosetsu Lua extension, as listed in a repo's `index.json`
/// `scripts` array.
///
/// [repo] (inherited from [Source]) holds the repo *root* URL (e.g.
/// `https://gitlab.com/shosetsuorg/extensions/-/raw/dev/`), from which both
/// [sourceCodeUrl] (`<repo>src/<lang>/<fileName>.lua`) and the native side's
/// `Require()` library lookups (`<repo>lib/<name>.lua`) are derived.
class SsSource extends Source {
  String? fileName;
  String? sourceCode;
  String? sourceCodeUrl;

  SsSource({
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
    this.fileName,
    this.sourceCode,
    this.sourceCodeUrl,
  });

  factory SsSource.fromJson(Map<String, dynamic> json) {
    final base = Source.fromJson(json);

    return SsSource(
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
      fileName: json['fileName'],
      sourceCode: json['sourceCode'],
      sourceCodeUrl: json['sourceCodeUrl'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['fileName'] = fileName;
    json['sourceCode'] = sourceCode;
    json['sourceCodeUrl'] = sourceCodeUrl;
    return json;
  }
}
