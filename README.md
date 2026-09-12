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

Under the hood, the bridge unifies several extension backends already wired into this repository:

- **Mangayomi** — JS/Dart extension scripts (anime, manga, novel)
- **Sora** — JS extension modules (anime, manga)
- **Aniyomi** — Tachiyomi-style anime/manga extensions
- **CloudStream** — video-only extensions
- **iReader** — novel extensions
- **Tsundoku** — anime/manga/novel extensions
- **Kotatsu** — manga extensions (`kotatsu-parsers`)
- **LnReader** — novel extensions
- **Legado** — 阅读/book-source novel extensions

You don't need to know which backend a given source uses. Once a source is installed, it exposes the same `SourceMethods` interface, so your app code stays backend-agnostic. From there, a typical app will:

1. initialize the bridge once at startup,
2. resolve installed extensions and repository data,
3. get a source's method handler,
4. call methods like `getPopular`, `getLatestUpdates`, or `search`,
5. optionally render the included extension manager UI.

## Platform support

Every backend above is available on Android, iOS, and Windows/Linux/macOS. Mangayomi, Sora, LnReader, and Legado are registered unconditionally. Aniyomi, CloudStream, iReader, Tsundoku, and Kotatsu each ship as two registrations that combine to cover every platform: a native Android build, and a desktop build that also runs on iOS — through a `java` subprocess on real desktops, or an interpreter-only OpenJDK runtime embedded in-process on iOS (since iOS can't spawn a subprocess or JIT).

| Extension source | Android | iOS | Windows / Linux / macOS |
|---|:---:|:---:|:---:|
| Mangayomi | ✅ | ✅ | ✅ |
| Sora | ✅ | ✅ | ✅ |
| LnReader | ✅ | ✅ | ✅ |
| Legado | ✅ | ✅ | ✅ |
| Aniyomi | ✅ | ✅ (embedded JVM) | ✅ |
| CloudStream | ✅ | ✅ (embedded JVM) | ✅ |
| iReader | ✅ | ✅ (embedded JVM) | ✅ |
| Tsundoku | ✅ | ✅ (embedded JVM) | ✅ |
| Kotatsu | ✅ | ✅ (embedded JVM) | ✅ |

The "embedded JVM" column note is the only real platform-specific caveat: on iOS those five backends run through the same fat JAR as desktop, but driven by an in-process, interpreter-only OpenJDK Zero VM instead of a spawned `java` process, so expect JIT-level performance to not apply there.

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

### Torrent streaming (TorrServer addon)

Beyond extension sources, the bridge also ships an optional torrent-streaming engine built on [TorrServer](https://github.com/YouROK/TorrServer), wrapping [`ayman708-UX/torrserver_flutter`](https://github.com/ayman708-UX/torrserver_flutter)'s architecture. It's registered as an `Addon`, not a `SourceMethods` backend, so it's reached through `AddonManager` instead:

```dart
import 'package:get/get.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';

final addon = Get.find<AddonManager>().get<TorrServerAddon>();

if (!await addon.isInstalled()) {
  await addon.install(); // downloads the TorrServer binary at runtime
}

final url = await addon.startStream(url: magnetOrTorrentUrl);
// hand `url` to your player, then call addon.stopStream() when done
```

Platform notes:

- **Windows/Linux/macOS/Android** — `TorrServerAddon` downloads the right binary at runtime (per-ABI on Android, via `dart:ffi`'s `Abi.current()`). How that downloaded file gets invoked on Android (subprocess vs. your own FFI loader) is left to the host app.
- **iOS** — TorrServer is statically linked in-process via a vendored `TorrServerKit.xcframework`, mirroring this plugin's own embedded-JVM approach; there's nothing to install through the addon there.
- TorrServer itself is **GPL-3.0**. Statically linking it into the iOS binary makes the whole iOS app a combined work under FSF guidance (source-availability obligations apply), whereas the subprocess model on desktop/Android stays "mere aggregation." Confirm this fits your distribution before shipping the iOS target.

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
| `AddonManager` | Manages installable addons (e.g. `TorrServerAddon`) |
| `Addon` | Base type for an installable addon |
| `TorrServerAddon` | Torrent-streaming addon (`startStream`/`stopStream`) |

## Credits & third-party licenses

This project's own license is the [Unabandon Public License (UPL)](LICENSE) — a license that explicitly incorporates and extends **GPLv3**, chosen specifically because some of the services below vendor GPL-3.0-licensed source directly. Services whose whole backend source was taken from another project are credited here with that project's license:

| Service | Upstream source | License |
|---|---|---|
| Aniyomi | [aniyomiorg/aniyomi](https://github.com/aniyomiorg/aniyomi) | Apache-2.0 |
| CloudStream | [recloudstream/cloudstream](https://github.com/recloudstream/cloudstream) | GPL-3.0 |
| Tsundoku | [tsundoku-otaku/tsundoku](https://github.com/tsundoku-otaku/tsundoku) | Apache-2.0 |
| Kotatsu | [KotatsuApp/Kotatsu](https://github.com/KotatsuApp/Kotatsu) | GPL-3.0 |
| Legado | [RyanYuuki/AnymeXExtensionRuntimeBridge](https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge) | UPL |
| Mangayomi | [kodjodevf/mangayomi](https://github.com/kodjodevf/mangayomi) | Apache-2.0 |
| Torrent streaming (`TorrServerAddon`) | [ayman708-UX/torrserver_flutter](https://github.com/ayman708-UX/torrserver_flutter), embedding [YouROK/TorrServer](https://github.com/YouROK/TorrServer) | GPL-3.0 |

Sora, iReader, and LnReader are original implementations of their respective public extension formats, not ports of another project's source, so no separate license applies beyond this repo's own.

See [LICENSE](LICENSE) for the full UPL text.

See [LICENSE](LICENSE) for the full UPL text.
