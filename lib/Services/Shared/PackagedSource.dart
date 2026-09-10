import '../../Models/Source.dart';

/// Base class for sources that are delivered as an installable package
/// (an APK on Android, a JAR/APK on desktop) resolved from a Tachiyomi-style
/// repository.
///
/// Aniyomi, IReader and Tsundoku each have an Android and a desktop `Source`
/// subtype; every one of them added its own `pkgName` / `apkName` pair. Those
/// two fields live here so shared repo logic (see
/// [parseTachiyomiRepoIndex] / `detectTachiyomiUpdates` in `TachiyomiRepo.dart`)
/// can operate without knowing the concrete type. Subtype-specific extras
/// (`apkPath`, `apkUrl`, `isShared`, …) stay on the subclasses.
abstract class PackagedSource extends Source {
  String? pkgName;
  String? apkName;

  /// Absolute download URL when the repository states one outright — the
  /// `index.pb` format does. Left `null` for `index.min.json` repos, where
  /// subclasses derive the URL from [iconUrl] + [apkName].
  String? apkUrlOverride;

  /// Prebuilt desktop JAR published alongside the APK, when the repo has one.
  String? jarUrl;

  PackagedSource({
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
    this.pkgName,
    this.apkName,
    this.apkUrlOverride,
    this.jarUrl,
  });
}
