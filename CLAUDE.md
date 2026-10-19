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
- `init({getDirectory, isarInstance?, network?, onLog})` — idempotent. Builds the
  global `BridgeContext`, opens Isar if not supplied, registers `ExtensionManager` and
  `AddonManager` in GetX.
- `BridgeContext` — global service locator: `isar`, `getDirectory` callback,
  optional `BridgeNetwork` (the host's whole network stack, see Network layer), `onLog`.
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
| **CloudStream** | `CloudStreamExtensions` / `CloudStreamDesktopExtensions` | Android + desktop | `CloudStreamSourceMethods` extends `BridgeSourceMethods`; video-only (no page list). Android records the preferences the extension reads/writes (`AndroidPreferenceRecorder`) and shows them as generic switch/text fields; desktop builds the extension's own settings screen off-screen and reads it as preferences (see Network layer). |
| **iReader** | `IReaderExtensions` / `IReaderDesktopExtensions` | Android + desktop | Novels. |
| **Tsundoku** | `TsundokuExtensions` / `TsundokuDesktopExtensions` | Android + desktop | |
| **LnReader** | `LnReaderExtensions` | all (incl. iOS) | Independent backend for LNReader novel plugins. Reads the LNReader `plugins.min.json` manifest (`Manifest.dart`); each plugin is a JS module run in its own QuickJS runtime via `LnReaderSourceMethods`. Self-contained polyfills under `Services/LnReader/Js/` (`Polyfills`, `Libs`, `HttpClient` = `@libs/fetch`, `Cheerio` + `DomSelector`, `HtmlParser`, `Storage` = `@libs/storage`). Novel-only. No Mangayomi coupling. |
| **Legado** | `LegadoExtensions` | all | Independent backend for Legado / 阅读 book sources (`gedoor/legado`). A repo is a JSON list of "书源" objects that carry their own HTML parse rules — no plugin binary; installing just stores the JSON. `RuleEngine/LegadoRuleEngine.dart` = pure-Dart JSOUP-style selector evaluator (`sel@attr`, `a\|\|b`, `##regex##repl###`, `{{key}}`/`{{page}}` url templates, `url,{options}`). `LegadoSourceMethods` runs it over `MClient` HTTP. Novel-only. Ported from `RyanYuuki/AnymeXExtensionRuntimeBridge`. |
| **Kotatsu** | `KotatsuExtensions` / `KotatsuDesktopExtensions` | Android + desktop | `kotatsu-parsers`-based manga backend; one shared parsers jar per repo (not one-APK-per-source) — installing/uninstalling a source just toggles it in a `kotatsu_active_sources[_desktop]` allow-list, nothing downloads per source. Manga-only. Android loads the jar's DEX directly via `dalvik.system.DexClassLoader`; desktop runs it through the same `dex2jar` conversion the other JVM-sidecar backends use, then loads the converted jar child-first (`KotatsuDesktopPluginClassLoader`, like Android's) and drives each parser through the shared reflection `KotatsuMangaParserWrapper`, so a jar built against a newer parsers API than the vendored one (e.g. Kotatsu-Redo's `MangaParserSource`) still links. See `runtimeManager/KOTATSU_NOTES.md`. Ported from `RyanYuuki/AnymeXExtensionRuntimeBridge`. |
| **Aidoku** | `AidokuExtensions` | all (incl. iOS) | Independent backend for Aidoku manga sources (`Aidoku-Community/sources`). A repo is a Tachiyomi-style `index.min.json` (a `{"sources": [...]}` wrapper, not a bare array); each source is a `.aix` zip (Rust->WASM32 module + `Source.json` manifest + icon) — `installSource` downloads it and keeps only the extracted `.wasm` (base64, in `AidokuSource.wasmBytesBase64`). Manga-only. `AidokuSourceMethods` keeps one `AidokuWorker` per source (`AidokuWorker.dart`): a background isolate that owns the `AidokuRuntime` (`AidokuRuntime.dart`) so the interpreter never blocks the UI (a 500-chapter MangaDex feed takes about a minute in the debug interpreter); HTTP (`MClient`, cookies), `defaults` (`KvStore`) and logging are proxied back to the main isolate, results cross as JSON, and `PageUrl.process` calls back into the worker. Inside the worker: the `Engines/WasmEngine/WasmEngine.dart` (`package:wasd`) instance, the Postcard decode and the exported `get_search_manga_list`/`get_manga_update`/`get_page_list` calls, serialised per source. A source's `settings.json` defaults are extracted from the `.aix` at install (`AidokuDefaults.dart`, stored as `AidokuSource.defaults`; already-installed sources fetch them once on first use) and answer `defaults_get` until the user sets a value. `AidokuHost.dart` implements the resource-descriptor (`Rid`) host ABI the wasm exports call into - `net`, `html` (DOM via `package:html`; `AidokuSelector.dart` adds the SwiftSoup pseudo-selectors `:contains`/`:containsOwn`/`:has`/`:eq`; `parse_fragment` returns a document whose `<body>` holds the fragment, like SwiftSoup's `parseBodyFragment`), `std`/`env`, `defaults`; `js` runs `context_*` on QuickJS (`flutter_qjs`; the `webview_*` calls return errors); `canvas` is real on `package:image` (`AidokuImages.dart` images/blits, `AidokuPaths.dart` path fill/stroke/dash rasteriser and bitmap-font text; decode/encode go through `compute`, the only isolate use), and `net.get_image` + `process_page_image`/`get_image_request` run when a page carries context: `PageUrl.process` (not in JSON) is applied by the app's reader/downloader to the fetched bytes (Mangago unscramble). `parse_date` honours the Swift format/timezone (`AidokuDates.dart`), `sleep`/`set_rate_limit` are real, and `readBytes` copies out of wasm memory (a view was corrupting POST bodies). The `url` default comes from `source.json` `info.urls[0]`. `getPageList` passes the chapter exactly as `get_manga_update` returned it, with the manga it came from (tracked per chapter key). getPopular/getLatestUpdates use `get_manga_list` with a listing from `source.json`/`get_listings` picked by name (popular/latest patterns), else the `get_home` components (`AidokuHome.dart`), else `get_search_manga_list(null, page, [])`. Preferences: `getPreference`/`setPreference` are built from the `.aix` `settings.json` (stored in `defaults['__settings']`, `AidokuSettings.dart`): switch/select/segment/multi-select/text become `SourcePreference`s stored under `aidoku-<id>-pref-<key>` (the same keys `defaults_get` reads), a setting's `notification` calls `handle_notification`, and `basic` logins become username/password fields that call `handle_basic_login`. Not implemented: web logins (`handle_web_login` needs the app's web view), stepper/editable-list/button settings, `get_settings` (dynamic), filters UI (`filters.json`/`get_filters`), migration, deep links, alternate covers, number-typed defaults. Verified live against real community sources (Asura Scans, Mangakakalot) - `net`/`html`/Postcard decode all confirmed correct against actual responses. |

Platform gating is in `ExtensionManager._extensionManagers` via `Platform.isAndroid` /
`_jvmBackends` (`isWindows||isLinux||isMacOS||isIOS` — the desktop backends also run on
iOS through an embedded JVM, see `JavaEngine/` below).

### Repositories (`lib/Extensions/RepoGuard.dart`)

Every `addRepo` goes through `Extension.addRepoTask`: the link is cleaned up
(`normalizeRepoUrl`: trims, adds `https://`, GitHub `blob` page -> raw file),
one already added is skipped, and a repo is only saved when it parses to
sources of the requested type. Otherwise it fails with a `RepoException`
(exported; `toString()` is the user-facing message): unreachable / HTTP error,
a web page instead of an index, another manager's repo (`detectRepoFormat`
names it, matched against each backend's `repoFormats`), or one with no
sources of that type. `commitRepo` saves + selects a new repo and hands the
already-parsed list to `fetchExtensions`, so adding doesn't fetch twice.
`downloadRepoIndex`/`invalidRepo` are the shared building blocks.

### `Services/Shared/` — cross-backend helpers

- `JvmBackend.dart` - `JvmBackend` + `AndroidJvmBackend` / `DesktopJvmBackend`:
  the startup every JVM-plugin backend shares (plugin installed check,
  auto-update, `NativeNetwork.start`, boot the runtime, `NativeNetwork.attach`)
  and its dispose. Desktop data lives under `bridge/<javaDataDir>`.
- `JsonRepoBackend.dart` - `addRepo`/`fetchRepo` for the single-JSON-index
  backends (Mangayomi, Sora, LnReader, Legado, Aidoku) given their
  `parseRepoIsolate`; `repoFor` names the saved repo (Sora: module author).

- `PackagedSource.dart` — `abstract PackagedSource extends Source` holding the
  `pkgName` / `apkName` pair common to every APK/JAR-delivered source. `ASource`,
  `AdSource`, `TSource`, `TdSource`, `ISource`, `IdSource` all extend it.
- `TachiyomiRepo.dart` — for backends that read a Tachiyomi `index.min.json`
  (Aniyomi, IReader, Tsundoku — Android + desktop):
  `tachiyomiIndexUrl`, `tachiyomiFallbackRepoUrl` (jsDelivr mirror),
  `parseTachiyomiRepoIndex<T>({prefixes, factory, …})` (compute-safe), and
  `detectTachiyomiUpdates(ext, available, type)`. Each backend's
  `_parseExtensions` / `detectUpdates` is now a thin delegate.
  `fetchTachiyomiRepoIndex` tries a base URL's `index.pb` before its
  `index.min.json` (current Mihon repos keep only an "update your app"
  placeholder in the JSON), each from its host then the jsDelivr mirror, and
  saves the index URL that worked.
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

## Network layer (`lib/Network/`, `runtimeManager/libraries/commonLib/.../network/`)

One session for every backend, owned by the host app through its single
`BridgeNetwork` (`lib/ExtensionBridge.dart`): `httpClient`/`downloadClient`
(read on every request, so a client the host rebuilds is picked up at once),
cookie jar, User-Agent (`bridgeUserAgent()` - also what every WebView uses,
so a Cloudflare challenge cleared in the app's own WebView works for every
extension), DoH resolver, proxy and `presentChallenge`. Members other than
`httpClient` have defaults.

- `CloudflareSolver.dart` - clears a challenge for a URL: an offscreen
  `webview_all` session loads it with the app UA + jar cookies and waits for a
  fresh `cf_clearance` (written back to the jar); if that fails, shows
  `CloudflareChallengePage` via `BridgeNetwork.presentChallenge`. Deduped per
  host, prompts queued, a dismissed host isn't asked again for 10 min.
- `WebViewCookieSync.dart` - WebView cookie store <-> app jar.
- `BridgeWebView.dart` - background WebView tasks for JVM sources (request
  interception via fetch/XHR/resource hooks, script results): CloudStream's
  desktop `WebViewResolver`, Kotatsu's `evaluateJs`.
- `NativeNetwork.dart` - the JVM backends' side: `start()` answers their
  callbacks (`getCookies`/`setCookies`/`getUserAgent`/`solveCloudflare`/
  `webView`, logs; desktop + iOS over `JavaBridgeServer`, Android over
  `flutterKotlinBridge.network`/`.logger`), `attach(owner, send)` sends
  `{dns, proxy, userAgent}` (`initClient`) now and again on
  `DartotsuExtensionBridge.networkChanged()` (host calls it when settings change).
- `MClient.dart` - Dart backends: `MClient.init()` (normal requests) and
  `MClient.download()` (large downloads, no total timeout; extension packages,
  plugins, Kotatsu jars). Merges jar cookies, forces the app UA with
  `cf_clearance`, retries a plain `Request` once after the solver clears a
  challenge.

JVM side: `commonLib` `Network` (`applyTo(builder)`/`newClient()`), with
`UserAgentInterceptor`, `CloudflareInterceptor` (asks the app's solver, then
retries), network-level `CookieInterceptor` (app jar; forces the app UA with
`cf_clearance`), `FlutterCookieJar`, `NetworkBound` (rebuild on new settings)
and `BridgeWebView`. Aniyomi/Tsundoku (`NetworkHelper`), CloudStream
(`bridgeClient()`, `CloudflareKiller`), Kotatsu and iReader
(`BridgeHttpClients`) all build on it. No FlareSolverr.

CloudStream settings: Android never opens an extension's native settings
screen; it records the preferences the extension reads/writes as it runs
(`AndroidPreferenceRecorder`, `cloudStreamCommon` androidMain: attributes each
read/write by matching call-stack frames against the `PathClassLoader`
registered for each loaded plugin, since Android has no `StackWalker`) and
serves them as switch/text preferences (keys `store::key`).

Desktop builds the screen itself. `SourcePreferences.desktop.kt` runs the
plugin's `openSettings` under `UiCapture` (commonDesktopLib): `DialogFragment.show`
hands the fragment over, `PluginResources` reads the plugin's `resources.arsc`
and `res/layout` from its converted jar (through the jar's own URL, since the
bridge's class loader would answer from its parent first), `LayoutInflater`
builds stand-in widgets (`android.widget.*` sources in commonDesktopLib keep
text/checked/listeners; every other Android UI method no-ops instead of
throwing "Stub!"), and `ScreenReader`/`ScreenSettings` turn the tree into
`switch`/`text`/`list` preferences with keys `ui::<sheets>::<control>`.
Rows that open another sheet are followed one level (this presses them, so
their side effects run); saving reopens the screen, sets the control and
presses the sheet's save button so the extension stores the value itself.
A plugin whose screen yields nothing falls back to `PreferenceRecorder`'s
recorded keys (every `SharedPreferences` read/write attributed per class
loader via `StackWalker`, same `store::key` form).

## Support

- `lib/Logger.dart` — `Logger.log(msg, show)` -> `BridgeContext.onLog`.
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

CloudStream desktop jar from a terminal (loads every `.cs3` in a folder, prints how many loaded and which failed):

```
./runtimeManager/gradlew -p runtimeManager :cloudStream:cloudStreamDesktop:buildPlugin
python3 runtimeManager/scripts/cloudstream_test.py \
  runtimeManager/builds/cloudStreamDesktop/cloudStreamDesktop-plugin.jar plugins/ \
  --repo https://raw.githubusercontent.com/phisher98/cloudstream-extensions-phisher/refs/heads/builds/repo.json
```

`runtimeManager/` (the JVM backend JARs, out of scope above) builds via
`./gradlew buildEverything` (desktop + android + the `embedded-bridge.jar`
shim). iOS uses the desktop JARs; after changing `EmbeddedBridge.kt`, copy the
rebuilt `embedded-bridge.jar` into
`ios/dartotsu_extension_bridge/Sources/dartotsu_embedded_jvm/Runtime/`. See
`runtimeManager/EMBEDDED_IOS_NOTES.md`.

`analysis_options.yaml` uses `flutter_lints`.
