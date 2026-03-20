# Dartotsu Extension Bridge

`dartotsu_extension_bridge` is a rewritten Flutter plugin that lets your app load and use extension-style sources from Dart.

It is built for projects that want to:
- discover extension repositories,
- list installed and available sources,
- install, update, and uninstall Android extension packages,
- call source methods from a single Dart API,
- reuse optional extension-management UI widgets.

## What this plugin does

The bridge exposes a unified API over multiple extension systems included in this repository, including:
- **Mangayomi-style sources**
- **Aniyomi-style Android extensions**
- other source backends already wired into the package

From your Flutter app, you can:
- initialize the bridge once at startup,
- resolve installed extensions,
- fetch repository data,
- create source method handlers,
- request popular/latest/search/detail/page/video data,
- manage source preferences,
- show a prebuilt extension manager UI if wanted.

## Requirements

- Flutter `>=3.3.0`
- Dart `>=3.0.0 <4.0.0`
- **Android is required for full extension package install/uninstall support**

> Non-Android platforms can still use parts of the bridge, but Android-specific extension installation flows depend on Android permissions and package APIs.

## Install the plugin

Add the package to your app:

```yaml
dependencies:
  dartotsu_extension_bridge:
    git:
      url: https://github.com/aayush2622/DartotsuExtensionBridge.git
      ref: main
```

Then run:

```bash
flutter pub get
```

## Basic usage

Import the package:

```dart
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
```

Initialize it early in app startup:

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

Get the extension manager:

```dart
import 'package:get/get.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';

final extensionManager = Get.find<ExtensionManager>();
final currentManager = extensionManager.current.value;
```

Use a source:

```dart
final installed = currentManager.getInstalledRx(ItemType.anime).value;

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

## Optional UI helpers

The plugin exports ready-to-use widgets:
- `ExtensionManagerScreen`
- `ExtensionList`

These are useful if you want a quick extension settings / management screen without building one from scratch.

---

# Android host project setup

If you want the rewritten extension bridge to work correctly inside your Flutter app, you must also update the **Android host project**.

This is the most important part of the setup.

## 1) Add required permissions to `AndroidManifest.xml`

Add these permissions inside your app manifest, usually at:

- `android/app/src/main/AndroidManifest.xml`

Example:

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

### Notes

- `INTERNET` is needed for repository and source requests.
- package install/delete permissions are needed for extension APK workflows.
- storage/media permissions may be required depending on your extension flow and Android version.
- `QUERY_ALL_PACKAGES` is sensitive on modern Android versions, so make sure your app store/distribution policy allows your use case.

## 2) Add the Gradle package exclude

Add this line to your Android app Gradle packaging excludes so the build does not fail on the OSGI manifest conflict:

```gradle
exclude 'META-INF/versions/9/OSGI-INF/MANIFEST.MF'
```

Typical location:
- `android/app/build.gradle`
- or `android/app/build.gradle.kts` equivalent packaging config

Example in Groovy Gradle:

```gradle
android {
    packagingOptions {
        resources {
            exclude 'META-INF/versions/9/OSGI-INF/MANIFEST.MF'
        }
    }
}
```

## 3) Update `android/settings.gradle` for plugin loading

Because this bridge may need Android plugin projects discovered from Flutter's plugin dependency file, add the following to your Android `settings.gradle`.

```gradle
import groovy.json.JsonSlurper

flutterProjectRoot = rootDir.parentFile
def pluginsFile = new File(flutterProjectRoot, ".flutter-plugins-dependencies")

if (pluginsFile.exists()) {

    def json = new JsonSlurper().parse(pluginsFile)
    def androidPlugins = json.plugins.android

    androidPlugins.each { plugin ->

        def name = plugin.name
        def pluginDirectory = new File(plugin.path, "android")
        def settingsFile = new File(pluginDirectory, "settings.gradle")

        include ":$name"
        project(":$name").projectDir = pluginDirectory

        if (settingsFile.exists()) {
            apply from: settingsFile
        }
    }
}
```

### Where to put it

Usually in:
- `android/settings.gradle`

If your project already has custom plugin-loading logic, merge this carefully instead of duplicating plugin includes.

## 4) Sync and rebuild

After making the Android changes above, run:

```bash
flutter clean
flutter pub get
flutter build apk
```

If you are using Android Studio, also run a Gradle sync.

---

# Common integration checklist

Before reporting a bug, make sure your host app has all of these:

- the plugin added in `pubspec.yaml`,
- `DartotsuExtensionBridge.init(...)` called before use,
- Android manifest permissions added,
- packaging exclude added,
- `settings.gradle` plugin loading snippet added,
- app rebuilt after making Gradle changes.

## Public exports

Main import:

```dart
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
```

Useful exported types include:
- `DartotsuExtensionBridge`
- `ExtensionManager`
- `Extension`
- `SourceMethods`
- `Source`
- `DMedia`
- `DEpisode`
- `Pages`
- `Video`
- `SourcePreference`
- `ExtensionManagerScreen`
- `ExtensionList`

## License

See [LICENSE](LICENSE).
