# Dartotsu Extension Bridge

A Flutter plugin that bridges **Aniyomi** and **Mangayomi** style extension sources into a unified Dart API.

## Getting Started
It provides:
- Extension discovery (installed + available)
- Install / update / uninstall flows
- Source-level content methods (popular, latest, search, detail, pages, videos, preferences)
- Optional ready-to-use extension manager UI base classes
## Platform support
Plugin platforms declared in `pubspec.yaml`:
- Android
- iOS
- Linux
- macOS
- Windows

> Note: Aniyomi extensions are Android-only. On non-Android platforms, the manager falls back to Mangayomi.

## Installation

Add this package to your Flutter project dependencies (path, git, or pub source depending on your setup), then run:

```bash
flutter pub get
```

## Quick start

### 1) Initialize the bridge

Call `init` early in app startup.

```dart
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';

final bridge = DartotsuExtensionBridge();

await bridge.init(
  null,               // provide your own Isar instance or null to auto-create
  'my_app_data_dir',  // used for desktop db location
);
```

### 2) Access the extension manager

```dart
import 'package:get/get.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';

final extensionManager = Get.find<ExtensionManager>();
final manager = extensionManager.currentManager;

// Installed extensions
final installedAnime = await manager.getInstalledAnimeExtensions();

// Fetch available extensions from repos
final availableAnime = await manager.fetchAvailableAnimeExtensions([
  'https://raw.githubusercontent.com/your/repo/index.min.json',
]);
```

### 3) Query content from a source

```dart
final source = installedAnime.first;
final methods = source.methods;

final popular = await methods.getPopular(1);
final latest = await methods.getLatestUpdates(1);
final results = await methods.search('one piece', 1, []);

final detailed = await methods.getDetail(results.list.first);
```

### 4) Get pages/videos and preferences

```dart
final episode = detailed.episodes!.first;

final pages = await methods.getPageList(episode);
final videos = await methods.getVideoList(episode);

final prefs = await methods.getPreference();
if (prefs.isNotEmpty) {
  await methods.setPreference(prefs.first, true);
}
```

## Choosing the extension backend

The package supports two extension backends:
- `ExtensionType.mangayomi`
- `ExtensionType.aniyomi` (Android only)

Switch at runtime:

```dart
final extensionManager = Get.find<ExtensionManager>();
extensionManager.setCurrentManager(ExtensionType.mangayomi);
```

## UI helpers

If you want built-in scaffolding for extension management UI, use:
- `ExtensionManagerScreen`
- `ExtensionList`

These are exported by `dartotsu_extension_bridge.dart`.

## Public exports

Main library export:

```dart
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
```

This exposes core models and APIs including:
- `DartotsuExtensionBridge`
- `ExtensionManager`, `ExtensionType`
- `Extension`, `SourceMethods`
- `Source`, `DMedia`, `DEpisode`, `PageUrl`, `Pages`, `Video`, `SourcePreference`

## Notes

- The plugin persists settings and source metadata using Isar.
- On Windows, `flutter_inappwebview` environment setup is initialized when available.
- For Android Aniyomi install flows, APK install permission/user confirmation behavior depends on device settings.

## Development

```bash
flutter pub get
flutter analyze
```

## License

See [LICENSE](LICENSE).