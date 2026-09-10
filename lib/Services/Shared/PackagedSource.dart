import '../../Models/Source.dart';

/// Base class for sources that are delivered as an installable package
/// (an APK on Android, a JAR/APK on desktop) resolved from a Tachiyomi-style
/// repository.
///
/// Aniyomi, IReader and Tsundoku each have an Android and a desktop `Source`
/// subtype; every one of them added its own `pkgName` / `apkName` / `apkPath`
/// triple and a byte-identical `apkUrl` getter. Those live here now so the
/// shared repo + installer logic (`TachiyomiRepo.dart`,
/// `TachiyomiJniDesktopExtension`) can operate without knowing the concrete
/// type. Subtype-specific extras (`isShared`, …) stay on the subclasses.
abstract class PackagedSource extends Source {
  String? pkgName;
  String? apkName;

  /// Absolute download URL when the repository states one outright — the
  /// `index.pb` format does, and the JSON parser now derives one too. Left
  /// `null` only when there's no `apkName` to build a URL from.
  String? apkUrlOverride;

  /// Prebuilt desktop JAR published alongside the APK, when the repo has one.
  String? jarUrl;

  /// Absolute path of the package file on disk once installed (desktop) — used
  /// to delete the old file on update / uninstall. `null` before install and
  /// on the Android backends, which uninstall by package name instead.
  String? apkPath;

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
    this.apkPath,
  });

  /// Download URL for the package. Prefers an explicit [apkUrlOverride];
  /// otherwise reconstructs it from the Tachiyomi repo layout
  /// (`<repo>/apk/<file>`, with `<repo>` recovered from [iconUrl]).
  String? get apkUrl {
    final override = apkUrlOverride;
    if (override != null && override.isNotEmpty) return override;

    final apk = apkName;
    final icon = iconUrl;
    if (apk == null || apk.isEmpty) return null;
    if (icon == null || icon.isEmpty) return null;

    final base = icon.replaceFirst('icon/', 'apk/');
    final lastSlash = base.lastIndexOf('/');
    if (lastSlash == -1) return '';

    return '${base.substring(0, lastSlash)}/$apk';
  }
}
