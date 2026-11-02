import '../../Models/Source.dart';

abstract class CloudStreamSource extends Source {
  String? internalName;
  String? pluginUrl;
  String? sourcePlugin;

  CloudStreamSource({
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
    this.sourcePlugin,
  });
}
