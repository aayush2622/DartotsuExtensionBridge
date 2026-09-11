# CLAUDE.md

Index of the **Dart** side of `dartotsu_extension_bridge` (everything under `lib/`).
The `runtimeManager/`, `android/`, `ios/`, `linux/`, `windows/` Kotlin/Java/native code is out of scope here.

## What this package is

A Flutter plugin that exposes **one Dart API** for discovering, installing and calling
"extension-style" content sources (anime / manga / novel) regardless of which backend
ecosystem a given source comes from (Mangayomi, Sora, Aniyomi, CloudStream, iReader,
Tsundoku, …). Consumers `init()` once, then work through `Extension` + `SourceMethods`.

- Package name: `dartotsu_extension_bridge` (see `pubspec.yaml`)
- State management: **GetX** (`Get.put` / `Get.find`)
- Persistence: **Isar** key-value store (`lib/Settings/KvStore.dart`)
- Public surface re-exported from `lib/dartotsu_extension_bridge.dart`

## Entry point & lifecycle

`lib/dartotsu_extension_bridge.dart` is just the barrel file (`library;` + `export`s).
The `DartotsuExtensionBridge` class, `BridgeContext`, `BridgeNetwork` and `GetDirectory`
actually live in **`lib/ExtensionBridge.dart`** (re-exported from the barrel). Note this
is a *different* file from `lib/Extensions/ExtensionBridge.dart` (the `abstract class
ExtensionBridge` transport) — same base name, different directory.

`DartotsuExtensionBridge` (`lib/ExtensionBridge.dart`)
- `init({getDirectory, http?, isarInstance?, network?, onLog})` — idempotent. Builds the
  global `BridgeContext`, opens Isar if not supplied, registers `ExtensionManager` and
  `AddonManager` in GetX.
- `BridgeContext` — global service locator: `isar`, `http` client, `getDirectory`
  callback, optional `BridgeNetwork` (dns / proxy / cookies), `onLog`.
- `GetDirectory` typedef — host app must supply persistent dir resolution
  (`subPath`, `useCustomPath`, `useSystemPath`).
- `dispose()` — tears down `ExtensionManager` (which disposes every backend,
  including the LnReader per-source JS runtimes).

## Core abstractions (`lib/Extensions/`, `lib/Models/`)

| File | Role |
|---|---|
| `ExtensionManager.dart` | GetX controller. Holds all `Extension` managers, the `current` map (`ItemType -> Extension`), and a `Source.runtimeType -> SourceMethods` factory table. `switchManager`, `createSourceMethods`, `get<T>()`/`find<T>()`. Adds `Source.methods` extension getter. |
| `AddonManager.dart` | GetX service for `Addon`s (currently only `LibtorrentAddon`). Update checks. |
| `Extensions/Extensions.dart` | `abstract class Extension` — the per-ecosystem manager. Per-`ItemType` `ExtensionState` (installed/available/repos/languages as Rx). Repo CRUD, language filtering, version compare, init state machine (`InitState`, `ensureInitialized`). Also defines `Repo`. `enum ItemType { manga, anime, novel }` (that order — `anime.index == 1`) lives in `Models/Source.dart`. |
| `Extensions/SourceMethods.dart` | `abstract class SourceMethods` — the uniform per-source API: `getPopular`, `getLatestUpdates`, `search`, `getDetail`, `getPageList`, `getVideoList`, `getNovelContent`, `getPreference`, `setPreference`. |
| `Extensions/BridgeSourceMethods.dart` | `SourceMethods` base for backends that call across an `ExtensionBridge` (JSON marshalling of `DMedia`/`DEpisode`). Used by CloudStream + Aniyomi. |
| `Extensions/ExtensionBridge.dart` | `abstract ExtensionBridge` + `MethodChannelBridge` (Android platform channel) and `JniExtensionBridge` (desktop JNI). |
| `Extensions/DownloadablePlugin.dart` | Base for downloadable helper plugins (JAR/APK) resolved from `plugins.json`; resumable download with retry, tracks `installed`, `availableInRepo`, download `progress`. Each desktop backend subclasses it. |
| `Extensions/ExtensionSettings.dart` | `ExtensionSetting` UI-model (`normal`/`switchType`/`slider`/`inputBox`) returned by `Extension.settings(context)`. |
| `Extensions/Addon.dart` | `abstract class Addon` (install/uninstall/update/checkForUpdate). |

### Data models (`lib/Models/`) — all plain JSON classes

- `Source.dart` — `Source` (id, name, baseUrl, lang, version, `itemType`, `repo`, `hasUpdate`) + `enum ItemType`.
- `DMedia.dart` — media/series (title, cover, genres, `List<DEpisode> episodes`).
- `DEpisode.dart` — one episode/chapter; parses fuzzy `episodeNumber`.
- `Pages.dart` / `Page.dart` — `Pages { List<DMedia> list; hasNextPage }`, `PageUrl { url, headers }`.
- `Video.dart` — `Video` (url, quality, headers) + `Track`, `TimeStamp`.
- `SourcePreference.dart` — preference descriptors (checkbox / switch / list / multiselect / edittext).

## Backends (`lib/Services/<Name>/`)

Each backend provides an `Extension` subclass (registered in `ExtensionManager._extensionManagers`)
and a matching `SourceMethods` implementation, plus its own `Models/Source.dart` subtype
used as the factory key.

| Backend | Manager class(es) | Platforms | Notes |
|---|---|---|---|
| **Mangayomi** | `MangayomiExtensions` | all (incl. iOS) | Repo of JS/Dart source scripts. Heavy sub-tree — see below. |
| **Sora** | `SoraExtensions` | all (incl. iOS) | JS "modules"; no novel support. `Services/Sora/JsEngine/`. |
| **Aniyomi** | `AniyomiExtensions` (Android) / `AniyomiDesktopExtensions` (desktop) | Android + desktop | Android: APK extensions via platform channel + `install_plugin`. Desktop: JNI/sidecar bridge into `runtimeManager`. `Generated/` = jnigen output. |
| **CloudStream** | `CloudStreamExtensions` / `CloudStreamDesktopExtensions` | Android + desktop | `CloudStreamSourceMethods` extends `BridgeSourceMethods`; video-only (page list / prefs unimplemented). |
| **iReader** | `IReaderExtensions` / `IReaderDesktopExtensions` | Android + desktop | Novels. |
| **Tsundoku** | `TsundokuExtensions` / `TsundokuDesktopExtensions` | Android + desktop | |
| **LnReader** | `LnReaderExtensions` | all (incl. iOS) | Independent backend for LNReader novel plugins. Reads the LNReader `plugins.min.json` manifest (`Manifest.dart`); each plugin is a JS module run in its own QuickJS runtime via `LnReaderSourceMethods`. Self-contained polyfills under `Services/LnReader/Js/` (`Polyfills`, `Libs`, `HttpClient` = `@libs/fetch`, `Cheerio` + `DomSelector`, `HtmlParser`, `Storage` = `@libs/storage`). Novel-only. No Mangayomi coupling. |
| **Legado** | `LegadoExtensions` | all | Independent backend for Legado / 阅读 book sources (`gedoor/legado`). A repo is a JSON list of "书源" objects that carry their own HTML parse rules — no plugin binary; installing just stores the JSON. `RuleEngine/LegadoRuleEngine.dart` = pure-Dart JSOUP-style selector evaluator (`sel@attr`, `a\|\|b`, `##regex##repl###`, `{{key}}`/`{{page}}` url templates, `url,{options}`). `LegadoSourceMethods` runs it over `MClient` HTTP. Novel-only. Ported from `RyanYuuki/AnymeXExtensionRuntimeBridge`. |
| **Kotatsu** | `KotatsuExtensions` | Android only | `kotatsu-parsers`-based manga backend; one shared parsers jar per repo (not one-APK-per-source) — installing/uninstalling a source just toggles it in a `kotatsu_active_sources` allow-list, nothing downloads per source. Manga-only. Desktop deliberately unwired: native loading goes through `dalvik.system.DexClassLoader`, Android-only. See `runtimeManager/KOTATSU_NOTES.md`. Ported from `RyanYuuki/AnymeXExtensionRuntimeBridge`. |

Platform gating is in `ExtensionManager._extensionManagers` via `Platform.isAndroid` /
`_jvmBackends` (`isWindows||isLinux||isMacOS||isIOS` — the desktop backends also run on
iOS through an embedded JVM, see `JavaEngine/` below).

### `Services/Shared/` — cross-backend helpers

- `PackagedSource.dart` — `abstract PackagedSource extends Source` holding the
  `pkgName` / `apkName` pair common to every APK/JAR-delivered source. `ASource`,
  `AdSource`, `TSource`, `TdSource`, `ISource`, `IdSource` all extend it.
- `TachiyomiRepo.dart` — for backends that read a Tachiyomi `index.min.json`
  (Aniyomi, IReader, Tsundoku — Android + desktop):
  `tachiyomiIndexUrl`, `tachiyomiFallbackRepoUrl` (jsDelivr mirror),
  `parseTachiyomiRepoIndex<T>({prefixes, factory, …})` (compute-safe), and
  `detectTachiyomiUpdates(ext, available, type)`. Each backend's
  `_parseExtensions` / `detectUpdates` is now a thin delegate.
  CloudStream and IReader-desktop use their own repo formats and don't go
  through this.

### Mangayomi sub-tree (`lib/Services/Mangayomi/`)

- `Eval/dart/` — runs Dart-based sources through the **`d4rt`** interpreter
  (`Eval/dart/service.dart` = `DartExtensionService`; `bridge/` registers host classes,
  `model/` = interpreter-visible model classes).
- `Eval/javascript/` — JS-based sources via `flutter_qjs`: polyfills for
  http / dom / preferences / extractors (`service.dart` is the entry).
- `anime_extractors/` — ~16 host-video extractors (filemoon, streamwish, voe, dood, okru, …).
- `cryptoaes/` — `crypto_aes.dart`, `deobfuscator.dart`, `js_unpacker.dart`.
- `Util/` — `ChapterRecognition`, xpath/dom helpers, preference providers, `lib.dart`.
- `Models/Source.dart` — `MSource` (also re-exported from the package root).

## Engines (`lib/Engines/`)

| Dir | Purpose |
|---|---|
| `JavaScriptEngine/JsEngine.dart` | `JsEngineEnv` singleton wrapping a shared `flutter_qjs` `QuickJsRuntime2`. |
| `JavaEngine/` | Talk to a JVM that hosts Aniyomi/CloudStream desktop runtime. `JavaBridgeServer.dart` (localhost HTTP, port 4567), `JavaHandler.dart`, `JavaInstaller.dart`. Transports implement `JavaBridge`: `Bridge/JniBridge.dart` (in-process JNI via `package:jni`), `Bridge/SidecarBridge.dart` (out-of-process `java -jar`, desktop), `Bridge/EmbeddedJvmBridge.dart` (iOS — one embedded interpreter-only OpenJDK Zero VM via method channel `dartotsu_extension_bridge/embedded_jvm`; native side in `ios/`, Kotlin entrypoint `EmbeddedBridge` in `runtimeManager/libraries/commonDesktopLib`, and `runtimeManager/EMBEDDED_IOS_NOTES.md`). `Bridge/JavaBridgeFactory.dart` picks per platform. |
| `TorrentEngine/` | libtorrent via `dart:ffi` (`ffi_bindings.dart`, `LibtorrentFlutter.dart` session + HTTP streaming server + tracker fetch, `LibTorrentAddon.dart` = the `Addon`, `Models.dart`). |

## Support

- `lib/Logger.dart` — `Logger.log(msg, show)` -> `BridgeContext.onLog`.
- `lib/NetworkClient.dart` — `MClient.init()` builds an `InterceptedClient` (`http_interceptor`), reusing the host `http` client unless `useDartHttpClient`.
- `lib/Services/Network.dart` — `BridgeChannels`: method channels `flutterKotlinBridge.network` / `.logger`, wiring native network + logging back into Dart (Android via `MethodChannel`, desktop via `JavaBridgeServer`).
- `lib/Settings/KvStore.dart` — `KvEntry` Isar collection + `KvStore` with debounced write queue; top-level `getVal<T>` / `setVal` helpers used everywhere for persistence. `KvStore.g.dart` is generated (`build_runner`).

## Conventions

- Directories and most files are **PascalCase** (`Extensions/`, `SourceMethods.dart`); the Mangayomi `Eval/` sub-tree (`Eval/dart`, `Eval/javascript`) is snake_case. New code should follow the PascalCase norm outside `Eval/`.
- New backend = new `Services/<Name>/` with an `Extension` subclass + `SourceMethods` + `Models/Source.dart` subtype, then add it to `ExtensionManager._extensionManagers` and it self-registers its factory via `sourceMethodFactories`.
- Async init is guarded by `Completer`s and `InitState`; call `ensureInitialized()` / `runIfReady()` rather than assuming readiness.
- Persist through `getVal`/`setVal`, never touch Isar directly.
- `*.g.dart` and `Services/**/Generated/**` (jnigen) are generated — don't hand-edit.
- `_parseExtensions` static methods are passed to `compute()` — keep them (and
  anything they call) isolate-safe: no `DartotsuExtensionBridge.context`, so log
  with `debugPrint`, not `Logger`.

## Build / codegen / test

```
dart run build_runner build --delete-conflicting-outputs   # KvStore.g.dart
dart run jnigen --config jnigen_aniyomi.yaml                # + jnigen_cloud_stream.yaml, jnigen_ireader.yaml
flutter test                                                # test/ — pure-Dart model + helper unit tests
dart analyze lib test
```

`runtimeManager/` (the JVM backend JARs, out of scope above) builds via
`./gradlew buildEverything` (desktop + android + the `embedded-bridge.jar`
shim) and `./gradlew buildAllPlugins -PiosRuntime=true` for the iOS variant
(Chromium/JOGL/JNA stripped). `./gradlew printBuildVariants` lists them; see
`runtimeManager/EMBEDDED_IOS_NOTES.md`.

`analysis_options.yaml` uses `flutter_lints`.
