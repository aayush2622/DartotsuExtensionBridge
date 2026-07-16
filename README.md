# Dartotsu Extension Bridge

`dartotsu_extension_bridge` is a Flutter plugin that gives your app a single Dart API for discovering, installing, and using extension-style content sources. Instead of writing separate integrations for each extension system, you initialize the bridge once and work through one consistent interface for everything downstream: repositories, installed sources, search, media details, and playback pages.

The plugin was built for apps that need to:

- discover and browse extension repositories,
- list installed and available sources,
- install, update, and uninstall extension packages,
- call source methods (popular, latest, search, details, pages, video) from Dart,
- manage per-source preferences,
- optionally drop in prebuilt UI widgets for extension management, without building that screen from scratch.

## What this plugin does

Under the hood, the bridge unifies several extension backends already wired into this repository, including:

- **Mangayomi-style sources**
- **Aniyomi-style Android extensions**
- other source backends bundled with the package

You don't need to know which backend a given source uses. Once a source is installed, it exposes the same `SourceMethods` interface, so your app code stays backend-agnostic. From there, a typical app will:

1. initialize the bridge once at startup,
2. resolve installed extensions and repository data,
3. get a source's method handler,
4. call methods like `getPopular`, `getLatestUpdates`, or `search`,
5. optionally render the included extension manager UI.

## Platform support

The bridge doesn't enable every extension source on every platform — each source is registered conditionally based on `Platform.isAndroid`, `Platform.isWindows`, `Platform.isLinux`, and `Platform.isMacOS`. Mangayomi and Sora are registered unconditionally, so they're the only sources available on iOS. Aniyomi, CloudStream, and Tsundoku each ship as two separate registrations — an Android build and a desktop build — which combine to cover both platforms. iReader is desktop-only.

| Extension source | Android | iOS | Windows / Linux / macOS |
|---|:---:|:---:|:---:|
| Mangayomi | ✅ | ✅ | ✅ |
| Sora | ✅ | ✅ | ✅ |
| Aniyomi | ✅ | ❌ | ✅ |
| CloudStream | ✅ | ❌ | ✅ |
| Tsundoku | ✅ | ❌ | ✅ |
| iReader | ❌ | ❌ | ✅ |

A few things fall out of this:

- **Android** gets Mangayomi, Sora, and the Android builds of Aniyomi, CloudStream, and Tsundoku.
- **Windows/Linux/macOS** get Mangayomi, Sora, the desktop builds of Aniyomi, CloudStream, and Tsundoku, plus iReader (desktop-only, no Android equivalent).
- **iOS** only gets Mangayomi and Sora — none of the Aniyomi, CloudStream, Tsundoku, or iReader sources are registered on that platform.

If your app targets iOS, plan around Mangayomi/Sora-backed content only. If you need the broader extension ecosystem (Aniyomi, CloudStream, Tsundoku, iReader), target Android and/or desktop.

## Requirements

- Flutter `>=3.3.0`
- Dart `>=3.0.0 <4.0.0`
- Android, specifically, for full extension package install/uninstall support

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  dartotsu_extension_bridge:
    git:
      url: https://github.com/aayush2622/DartotsuExtensionBridge.git
      ref: main
```

Then fetch it:

```bash
flutter pub get
```

## Basic usage

Import the package:

```dart
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
```

### Initialize the bridge

Call `init` early in app startup, before any other bridge calls. It needs a directory resolver so the bridge knows where to store extension data:

```dart
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';

Future<Directory?> getBridgeDirectory({
  String? subPath,
  bool useCustomPath = false,
  bool useSystemPath = false,
}) async {
  final base = await getApplicationSupportDirectory();
  final dir = subPath == null ? base : Directory('${base.path}/$subPath');

  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  return dir;
}

Future<void> setupBridge() async {
  await DartotsuExtensionBridge.init(
    getDirectory: getBridgeDirectory,
  );
}
```

### Access the extension manager

Once initialized, grab the manager through `get`:

```dart
import 'package:get/get.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';

final extensionManager = Get.find<ExtensionManager>();
final currentManager = manager[type].state(type);
```

### Call a source

Every installed source exposes a `methods` object with the same shape, regardless of which backend it came from:

```dart
final installed = currentManager.installed.value;

if (installed.isNotEmpty) {
  final source = installed.first;
  final methods = source.methods;

  final popular = await methods.getPopular(1);
  final latest = await methods.getLatestUpdates(1);
  final results = await methods.search('one piece', 1, []);

  print(popular.list.length);
  print(latest.list.length);
  print(results.list.length);
}
```

---

# Android host project setup

The Dart-side API works out of the box, but **Android extension installation** depends on a few changes to your host app's Android project. This is the part most integration issues come from, so don't skip it.

## 1. Add required permissions

Add these to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
    <uses-permission android:name="android.permission.REQUEST_DELETE_PACKAGES" />
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />

    <uses-permission
        android:name="android.permission.QUERY_ALL_PACKAGES"
        tools:ignore="QueryAllPackagesPermission" />
    <uses-permission android:name="android.permission.UPDATE_PACKAGES_WITHOUT_USER_ACTION" />

    <uses-feature android:name="android.software.leanback" android:required="false" />
    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />

    <application
        android:label="Your App"
        android:icon="@mipmap/ic_launcher">
        <!-- your activities/services here -->
    </application>
</manifest>
```

What each group is for:

- **`INTERNET`** — required for repository and source network requests.
- **`REQUEST_INSTALL_PACKAGES` / `REQUEST_DELETE_PACKAGES`** — required for installing and removing extension APKs.
- **Storage / media permissions** — required depending on your extension flow and target Android version.
- **`QUERY_ALL_PACKAGES`** — this is a sensitive permission on modern Android and is subject to Play Store review policy. Confirm it fits your distribution channel before shipping.

## 2. Exclude the conflicting OSGI manifest

Extension package builds can conflict with an OSGI manifest entry during packaging. Add this exclude to your app's Gradle packaging config, typically in `android/app/build.gradle`:

```gradle
android {
    packagingOptions {
        resources {
            exclude 'META-INF/versions/9/OSGI-INF/MANIFEST.MF'
        }
    }
}
```

(If you're on Kotlin DSL, add the equivalent exclude to `build.gradle.kts`.)

## 3. Sync and rebuild

After making the changes above, do a clean rebuild:

```bash
flutter clean
flutter pub get
flutter build apk
```

If you're working in Android Studio, also trigger a Gradle sync so the IDE picks up the packaging change.

---

# Common integration checklist

Before filing a bug report, confirm your host app has all of the following:

- [ ] plugin added in `pubspec.yaml`
- [ ] `DartotsuExtensionBridge.init(...)` called before any other bridge usage
- [ ] Android manifest permissions added
- [ ] Gradle packaging exclude added
- [ ] app rebuilt (`flutter clean` + rebuild) after the Gradle change

Most reported issues trace back to one of these being missed, so it's worth double-checking before digging further.

## Public exports

Everything is available from the main import:

```dart
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
```

| Export | Purpose |
|---|---|
| `DartotsuExtensionBridge` | Entry point; call `init()` at startup |
| `ExtensionManager` | Manages installed/available extensions |
| `Extension` | Represents a single extension package |
| `SourceMethods` | Unified method interface for a source (popular, search, etc.) |
| `Source` | A content source exposed by an extension |
| `DMedia` | Media item model |
| `DEpisode` | Episode/chapter model |
| `Pages` | Page/content result model |
| `Video` | Video stream model |
| `SourcePreference` | Per-source configuration/preferences |
| `ExtensionManagerScreen` | Prebuilt UI for browsing/installing extensions |
| `ExtensionList` | Prebuilt UI for listing extensions |

## License

See [LICENSE](LICENSE).
