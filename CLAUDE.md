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
| `Extensions/ExtensionBridge.dart` | `abstract ExtensionBridge` + `MethodChannelBridge` (Android platform channel) and `JavaExtensionBridge` (wraps a `JavaBridge`: desktop sidecar / iOS embedded VM). |
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
| **Aniyomi** | `AniyomiExtensions` (Android) / `AniyomiDesktopExtensions` (desktop) | Android + desktop | Android: APK extensions via platform channel + `install_plugin`. Desktop/iOS: sidecar (desktop) or embedded VM (iOS) bridge into `runtimeManager`. |
| **CloudStream** | `CloudStreamExtensions` / `CloudStreamDesktopExtensions` | Android + desktop | `CloudStreamSourceMethods` extends `BridgeSourceMethods`; video-only (no page list). Desktop preferences come from `PreferenceRecorder` (see Network layer). |
| **iReader** | `IReaderExtensions` / `IReaderDesktopExtensions` | Android + desktop | Novels. |
| **Tsundoku** | `TsundokuExtensions` / `TsundokuDesktopExtensions` | Android + desktop | |
| **LnReader** | `LnReaderExtensions` | all (incl. iOS) | Independent backend for LNReader novel plugins. Reads the LNReader `plugins.min.json` manifest (`Manifest.dart`); each plugin is a JS module run in its own QuickJS runtime via `LnReaderSourceMethods`. Self-contained polyfills under `Services/LnReader/Js/` (`Polyfills`, `Libs`, `HttpClient` = `@libs/fetch`, `Cheerio` + `DomSelector`, `HtmlParser`, `Storage` = `@libs/storage`). Novel-only. No Mangayomi coupling. |
| **Legado** | `LegadoExtensions` | all | Independent backend for Legado / 阅读 book sources (`gedoor/legado`). A repo is a JSON list of "书源" objects that carry their own HTML parse rules — no plugin binary; installing just stores the JSON. `RuleEngine/LegadoRuleEngine.dart` = pure-Dart JSOUP-style selector evaluator (`sel@attr`, `a\|\|b`, `##regex##repl###`, `{{key}}`/`{{page}}` url templates, `url,{options}`). `LegadoSourceMethods` runs it over `MClient` HTTP. Novel-only. Ported from `RyanYuuki/AnymeXExtensionRuntimeBridge`. |
| **Kotatsu** | `KotatsuExtensions` / `KotatsuDesktopExtensions` | Android + desktop | `kotatsu-parsers`-based manga backend; one shared parsers jar per repo (not one-APK-per-source) — installing/uninstalling a source just toggles it in a `kotatsu_active_sources[_desktop]` allow-list, nothing downloads per source. Manga-only. Android loads the jar's DEX directly via `dalvik.system.DexClassLoader`; desktop runs it through the same `dex2jar` conversion the other JVM-sidecar backends use, then loads the converted jar with a plain parent-first `URLClassLoader` (no reflection wrapper needed there, unlike Android's child-first loader). See `runtimeManager/KOTATSU_NOTES.md`. Ported from `RyanYuuki/AnymeXExtensionRuntimeBridge`. |
| **Aidoku** | `AidokuExtensions` | all (incl. iOS) | Independent backend for Aidoku manga sources (`Aidoku-Community/sources`). A repo is a Tachiyomi-style `index.min.json` (a `{"sources": [...]}` wrapper, not a bare array); each source is a `.aix` zip (Rust->WASM32 module + `Source.json` manifest + icon) — `installSource` downloads it and keeps only the extracted `.wasm` (base64, in `AidokuSource.wasmBytesBase64`). Manga-only. `AidokuSourceMethods` keeps one `AidokuWorker` per source (`AidokuWorker.dart`): a background isolate that owns the `AidokuRuntime` (`AidokuRuntime.dart`) so the interpreter never blocks the UI (a 500-chapter MangaDex feed takes about a minute in the debug interpreter); HTTP (`MClient`, cookies), `defaults` (`KvStore`) and logging are proxied back to the main isolate, results cross as JSON, and `PageUrl.process` calls back into the worker. Inside the worker: the `Engines/WasmEngine/WasmEngine.dart` (`package:wasd`) instance, the Postcard decode and the exported `get_search_manga_list`/`get_manga_update`/`get_page_list` calls, serialised per source. A source's `settings.json` defaults are extracted from the `.aix` at install (`AidokuDefaults.dart`, stored as `AidokuSource.defaults`; already-installed sources fetch them once on first use) and answer `defaults_get` until the user sets a value. `AidokuHost.dart` implements the resource-descriptor (`Rid`) host ABI the wasm exports call into - `net`, `html` (DOM/select via `package:html`, not a full SwiftSoup-equivalent - no `:contains`/`:has`/`:matches`/nth-child formulas), `std`/`env`, `defaults`; `js` runs `context_*` on QuickJS (`flutter_qjs`; the `webview_*` calls return errors); `canvas` is real on `package:image` (`AidokuImages.dart` images/blits, `AidokuPaths.dart` path fill/stroke/dash rasteriser and bitmap-font text; decode/encode go through `compute`, the only isolate use), and `net.get_image` + `process_page_image`/`get_image_request` run when a page carries context: `PageUrl.process` (not in JSON) is applied by the app's reader/downloader to the fetched bytes (Mangago unscramble). `parse_date` honours the Swift format/timezone (`AidokuDates.dart`), `sleep`/`set_rate_limit` are real, and `readBytes` copies out of wasm memory (a view was corrupting POST bodies). The `url` default comes from `source.json` `info.urls[0]`. getPopular/getLatestUpdates use `get_manga_list` with a listing from `source.json`/`get_listings` picked by name (popular/latest patterns), else the `get_home` components (`AidokuHome.dart`), else `get_search_manga_list(null, page, [])`. Preferences: `getPreference`/`setPreference` are built from the `.aix` `settings.json` (stored in `defaults['__settings']`, `AidokuSettings.dart`): switch/select/segment/multi-select/text become `SourcePreference`s stored under `aidoku-<id>-pref-<key>` (the same keys `defaults_get` reads), a setting's `notification` calls `handle_notification`, and `basic` logins become username/password fields that call `handle_basic_login`. Not implemented: web logins (`handle_web_login` needs the app's web view), stepper/editable-list/button settings, `get_settings` (dynamic), filters UI (`filters.json`/`get_filters`), migration, deep links, alternate covers, number-typed defaults. Verified live against real community sources (Asura Scans, Mangakakalot) - `net`/`html`/Postcard decode all confirmed correct against actual responses. |

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
| `JavaEngine/` | Talk to a JVM that hosts Aniyomi/CloudStream desktop runtime. `JavaBridgeServer.dart` (localhost HTTP, port 4567 — Kotlin `Logger` and cookie callbacks post here; started on desktop *and* iOS), `JavaInstaller.dart`. Transports implement `Bridge/JavaBridge.dart`: `Bridge/SidecarBridge.dart` (one `java -jar` process per backend, desktop), `Bridge/EmbeddedJvmBridge.dart` (iOS — one embedded interpreter-only OpenJDK Zero VM via method channel `dartotsu_extension_bridge/embedded_jvm`; native side in `ios/`, Kotlin entrypoint `EmbeddedBridge` in `runtimeManager/libraries/commonDesktopLib`, and `runtimeManager/EMBEDDED_IOS_NOTES.md`). `Bridge/JavaBridgeFactory.dart` picks per platform. No jnigen/`package:jni`: an in-process JVM is one-per-process, so desktop uses sidecars. iOS runs the **same desktop plugin JARs** (no `-ios` variant; `DownloadablePlugin` picks the `desktop` row) — only Chromium/JCEF WebView is unavailable there (`CefHelper` refuses on `-Ddartotsu.runtime=ios`). iOS JVM logging: HotSpot output (`vfprintf`/`exit`/`abort` hooks), Java stdout/stderr (`EmbeddedBridge.installLogCapture` → `nativeLog`) and uncaught exceptions go to `Logger` as `[JVM] …` and to `bridge/logs/jvm.log` (rotated to `jvm.previous.log` each start); fatal reports land in `bridge/logs/hs_err.log` and are logged on the next start. |
| `TorrentEngine/` | libtorrent via `dart:ffi` (`ffi_bindings.dart`, `LibtorrentFlutter.dart` session + HTTP streaming server + tracker fetch, `LibTorrentAddon.dart` = the `Addon`, `Models.dart`). |
| `WasmEngine/WasmEngine.dart` | `WasmEngine` - thin wrapper around `package:wasd` (pure-Dart WebAssembly runtime, no native binaries). One instance per wasm module (own linear memory/state), unlike `JsEngineEnv`'s shared singleton. Used by Aidoku; `instantiate(bytes, imports)` requires every host import the module declares to be supplied by the caller. `call(name, args)` is async - host imports (e.g. Aidoku's `net`) may do real I/O, and wasd's interpreter transparently switches an export to its async invocation path if any host import it calls is async. |

## Network layer (`lib/Network/`, `lib/NetworkClient.dart`, `runtimeManager/libraries/commonLib/.../network/`)

One session for every backend, owned by the host app through `BridgeNetwork`:
its cookie jar, its User-Agent (`bridgeUserAgent()` - also what every WebView
uses, so a Cloudflare challenge cleared in the app's own WebView works for
every extension), DoH resolver and proxy.

- `CloudflareSolver.dart` - clears a challenge for a URL: an offscreen
  `webview_all` session loads it with the app UA + jar cookies and waits for a
  fresh `cf_clearance` (written back to the jar); if that fails, shows
  `CloudflareChallengePage` via `BridgeNetwork.presentChallenge`. Deduped per
  host, prompts queued, a dismissed host isn't asked again for 10 min.
- `WebViewCookieSync.dart` - WebView cookie store <-> app jar.
- `BridgeWebView.dart` - background WebView tasks for JVM sources (request
  interception via fetch/XHR/resource hooks, script results): CloudStream's
  desktop `WebViewResolver`, Kotatsu's `evaluateJs`.
- `NetworkSettingsSync.dart` - sends `{dns, proxy, userAgent}` to every
  running JVM backend (`initClient`) and re-sends on
  `DartotsuExtensionBridge.networkChanged()` (host calls it when settings change).
- `MClient` (`NetworkClient.dart`) - Dart backends: merges jar cookies, forces
  the app UA with `cf_clearance`, retries a plain `Request` once after the
  solver clears a challenge.
- `Services/Network.dart` (`BridgeChannels`) answers the JVM callbacks:
  `getCookies`/`setCookies`/`getUserAgent`/`solveCloudflare`/`webView`
  (desktop + iOS over `JavaBridgeServer`, Android over `flutterKotlinBridge.network`).

JVM side: `commonLib` `Network` (`applyTo(builder)`/`newClient()`), with
`UserAgentInterceptor`, `CloudflareInterceptor` (asks the app's solver, then
retries), network-level `CookieInterceptor` (app jar; forces the app UA with
`cf_clearance`), `FlutterCookieJar`, `NetworkBound` (rebuild on new settings)
and `BridgeWebView`. Aniyomi/Tsundoku (`NetworkHelper`), CloudStream
(`bridgeClient()`, `CloudflareKiller`), Kotatsu and iReader
(`BridgeHttpClients`) all build on it. No FlareSolverr.

CloudStream settings on desktop: `PreferenceRecorder` (commonDesktopLib)
records every `SharedPreferences` read/write per extension class loader;
`SourcePreferences.desktop.kt` serves them as switch/text preferences
(keys `store::key`) after probing the extension's settings screen off-screen.

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
- `*.g.dart` are generated — don't hand-edit.
- `_parseExtensions` static methods are passed to `compute()` — keep them (and
  anything they call) isolate-safe: no `DartotsuExtensionBridge.context`, so log
  with `debugPrint`, not `Logger`.

## Build / codegen / test

```
dart run build_runner build --delete-conflicting-outputs   # KvStore.g.dart
flutter test                                                # test/ — pure-Dart model + helper unit tests
dart analyze lib test
```

`runtimeManager/` (the JVM backend JARs, out of scope above) builds via
`./gradlew buildEverything` (desktop + android + the `embedded-bridge.jar`
shim). iOS uses the desktop JARs; after changing `EmbeddedBridge.kt`, copy the
rebuilt `embedded-bridge.jar` into
`ios/dartotsu_extension_bridge/Sources/dartotsu_embedded_jvm/Runtime/`. See
`runtimeManager/EMBEDDED_IOS_NOTES.md`.

`analysis_options.yaml` uses `flutter_lints`.
