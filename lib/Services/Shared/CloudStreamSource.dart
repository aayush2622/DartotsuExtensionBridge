import '../../Models/Source.dart';

/// Base class for CloudStream sources. Android's `CSource` and desktop's
/// `CdSource` were byte-identical past the class name - `internalName` /
/// `pluginUrl` live here now so `CloudStreamRepoBackend` can operate on them
/// generically, the same treatment `PackagedSource` got for the Tachiyomi
/// backends.
abstract class CloudStreamSource extends Source {
  String? internalName;
  String? pluginUrl;

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
  });
}
