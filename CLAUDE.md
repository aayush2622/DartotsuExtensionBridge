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
- Startup: `ExtensionManager.onInit` resolves the saved default per type (`<type>Manager` in `KvStore`, written
  by `switchManager`, which logs the change) and starts `initializeInstalled(type)` on each default, so its
  backend (and JVM sidecar) boots and its installed list loads at launch. A backend that is not a default
  boots only when asked (`initializeInstalled` / `ensureInitialized`, e.g. the app's source subscriptions).
  `Extension._trackInstalled` keeps `ExtensionState.loadingInstalled` true while the installed list loads.
- `dispose()` — tears down `ExtensionManager` (which disposes every backend,
  including the LnReader per-source JS runtimes).

## Toolkit (`lib/Toolkit/`, barrel `lib/toolkit.dart`)

Pure-Dart helpers with no state and no `init()` requirement, shared by any app on top of the bridge: `TitleMatch` (`titleRatio`), `Episodes` (`normalizeEpisodes` / `normalizeAll` / `prepareChapters` / seasons), `Languages` (`LanguageMatcher`, `languageMatcher`, generic `pickTrack<T>`), `FileNames` (`episodeNumberOf`), `Hls` (playlist parser and local playlist builders) and `SourceTester`. They were moved out of the Dartotsu app; keep new generic source logic here, not in the app. `test/toolkit_test.dart` covers them. `DartotsuExtensionBridge.init()` takes no required arguments (`defaultDirectory`, own Isar, plain client) and `DartotsuExtensionBridge.extensions` returns the manager.

## Downloads (`lib/Downloads/`, barrel `lib/downloads.dart`)

The file-level half of a download manager, moved out of the Dartotsu app: `fetchFile` (resumable `.part` file with `Range`, optional chunked parallel ranges, per-host pacing, 429 handling, `fetchWithRetry`), `downloadHls` (segments, keys, fMP4 init maps, local playlist, then `FfmpegAddon.remuxPlaylist` to mp4 or a playable folder; `probeHls`, `loadMaster`), `downloadPages` / `localizeNovelImages` (manga pages and novel images, type sniffed from the bytes), `Archives` (cbz unpack, epub to one HTML file, table of contents), `BookText`, `DownloadPaths` (root through `BridgeContext.getDirectory(subPath: 'downloads')`, per-service title folders, `.nomedia`), file-name helpers and `DownloadThrottle.limitKbps`. Requests go through `openStream` over `BridgeNetwork.downloadClient` (falls back to a plain `http.Client` when the host gave none) and abort through `DownloadCancel` (`AbortableRequest.abortTrigger`). The queue, task state, notifications and source lookup are still in the app. `test/downloads_test.dart` runs `fetchFile` against a loopback server (full file, resume, cancel).

## Core abstractions (`lib/Extensions/`, `lib/Models/`)

| File | Role |
|---|---|
| `ExtensionManager.dart` | GetX controller. Holds all `Extension` managers, the `current` map (`ItemType -> Extension`), and a `Source.runtimeType -> SourceMethods` factory table. `switchManager`, `createSourceMethods`, `get<T>()`/`find<T>()`. Adds `Source.methods` extension getter. |
| `AddonManager.dart` | GetX service for `Addon`s (TorrServer, FFmpeg, and the `JvmAddon` off Android). Update checks. |
| `Extensions/Extensions.dart` | `abstract class Extension` — the per-ecosystem manager. Per-`ItemType` `ExtensionState` (installed/available/repos/languages as Rx). Repo CRUD, language filtering, version compare, init state machine (`InitState`, `ensureInitialized`). Also defines `Repo`. `enum ItemType { manga, anime, novel }` (that order — `anime.index == 1`) lives in `Models/Source.dart`. |
| `Extensions/SourceMethods.dart` | `abstract class SourceMethods` — the uniform per-source API: `getPopular`, `getLatestUpdates`, `search`, `getDetail`, `getPageList`, `getVideoList`, `getNovelContent`, `getPreference`, `setPreference`. |
| `Extensions/BridgeSourceMethods.dart` | `SourceMethods` base for backends that call across an `ExtensionBridge` (JSON marshalling of `DMedia`/`DEpisode`). Used by CloudStream + Aniyomi. |
| `Extensions/ExtensionBridge.dart` | `abstract ExtensionBridge` + `MethodChannelBridge` (Android platform channel) and `JavaExtensionBridge` (wraps a `JavaBridge`: desktop sidecar / iOS embedded VM). |
| `Extensions/DownloadablePlugin.dart` | Base for downloadable helper plugins (JAR/APK) resolved from `plugins.json`; resumable download with retry (a 4xx other than 408/429 is not retried), tracks `installed`, `availableInRepo`, download `progress`. The index is fetched once per session; `fetchRemote(forceRefresh:)` refetches it when older than 20 s and keeps the old copy if that fails. Each backend subclasses it (desktop ones through `DesktopPlugin`, see *Desktop core jar*). It `implements PluginDependency`: `step` is its own `InstallStep` (shares its progress Rx), `steps` is everything an install takes, dependencies first, set by `plan({minimum, refresh})` (no download: each step becomes waiting / up to date with size, version, `replaces`) which also sets `updateAvailable` (the plugin itself **or** a dependency is outdated). `dependencies` are what it needs next to it: `download()` / `update()` run each dependency's `ensure(minimum: requires[key], latest: true)` first, so an install takes any newer core too; `update()` also runs when only a dependency is outdated (the plugin file is then left alone and `onUpdated` not called). `autoUpdate()` updates dependencies before itself, `ensure(minimum:, latest:)` installs/updates once however many callers ask, `installDependencies()` is what a starting backend calls (never throws; without network a self-contained jar still starts), `classpath()` the files to put in front of it. |
| `Extensions/ExtensionSettings.dart` | `ExtensionSetting` UI-model (`normal`/`switchType`/`slider`/`inputBox`) returned by `Extension.settings(context)`. |
| `Extensions/Addon.dart` | `abstract class Addon` (install/uninstall/update/checkForUpdate). |
| `Extensions/InstallStep.dart` | `InstallStep` (id `jre` / `core` / `plugin`, `StepStatus` waiting · checking · downloading · installing · done · upToDate · skipped · failed, live progress/bytes/speed, `version`, `replaces`, `detail`, `error`) and `PluginDependency` (`key`, `steps`, `plan`, `ensure`, `classpath`, `autoUpdate`, `cancel`), implemented by `DownloadablePlugin` and `JvmAddon`. |

### Data models (`lib/Models/`) — all plain JSON classes

- `Source.dart` — `Source` (id, name, baseUrl, lang, version, `itemType`, `repo`, `hasUpdate`) + `enum ItemType`.
- `Extension.reinstallSource` / `ExtensionUpdateConflict` (`Extensions/Extensions.dart`) — on Android (`AndroidApkInstallMixin`) a shared install of an already installed package waits for the system installer to close (app lifecycle leaves and returns) and compares `versionCode` before and after; unchanged means the installer refused the update (usually another signing key), so `installSource` throws `ExtensionUpdateConflict` and the app offers uninstall + reinstall. Fresh installs and private (app-folder) installs are not checked. Not verified on a device.
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
| **LnReader** | `LnReaderExtensions` | all (incl. iOS) | Independent backend for LNReader novel plugins. Reads the LNReader `plugins.min.json` manifest (`Manifest.dart`); each plugin is a JS module run in its own QuickJS runtime inside a background isolate (`LnReaderWorker`, same shape as `AidokuWorker`: `LnReaderSourceMethods` is only the main-isolate wrapper; the worker owns the runtime, the polyfills, Cheerio/DOM parsing and the chapter-list mapping, so a 3000-chapter `parseNovel` no longer stalls the UI; `@libs/fetch` requests are proxied back to the main isolate and served by `MClient`, `@libs/storage` keeps the plugin's map in the worker — seeded from `KvStore` at spawn — and sends every write back to be persisted; results cross as plain JSON maps; `clientFactory`/`readStore`/`writeStore`/`logSink` are static hooks for tests). Self-contained polyfills under `Services/LnReader/Js/` (`Polyfills`, `Libs`, `HttpClient` = `@libs/fetch`, `Cheerio` + `DomSelector`, `HtmlParser`, `Storage` = `@libs/storage`). Novel-only. No Mangayomi coupling. |
| **Legado** | `LegadoExtensions` | all | Independent backend for Legado / 阅读 book sources (`gedoor/legado`). A repo is a JSON list of "书源" objects that carry their own HTML parse rules — no plugin binary; installing just stores the JSON. `RuleEngine/LegadoRuleEngine.dart` = pure-Dart JSOUP-style selector evaluator (`sel@attr`, `a\|\|b`, `##regex##repl###`, `{{key}}`/`{{page}}` url templates, `url,{options}`). `LegadoSourceMethods` runs it over `MClient` HTTP. Novel-only. Ported from `RyanYuuki/AnymeXExtensionRuntimeBridge`. |
| **Kotatsu** | `KotatsuExtensions` / `KotatsuDesktopExtensions` | Android + desktop | `kotatsu-parsers`-based manga backend; one shared parsers jar per repo (not one-APK-per-source) — installing/uninstalling a source just toggles it in a `kotatsu_active_sources[_desktop]` allow-list, nothing downloads per source. Manga-only. Android loads the jar's DEX directly via `dalvik.system.DexClassLoader`; desktop runs it through the same `dex2jar` conversion the other JVM-sidecar backends use, then loads the converted jar child-first (`KotatsuDesktopPluginClassLoader`, like Android's) and drives each parser through the shared reflection `KotatsuMangaParserWrapper`, so a jar built against a newer parsers API than the vendored one (e.g. Kotatsu-Redo's `MangaParserSource`) still links. See `runtimeManager/KOTATSU_NOTES.md`. Ported from `RyanYuuki/AnymeXExtensionRuntimeBridge`. |
| **Aidoku** | `AidokuExtensions` | all (incl. iOS) | Independent backend for Aidoku manga sources (`Aidoku-Community/sources`). A repo is a Tachiyomi-style `index.min.json` (a `{"sources": [...]}` wrapper, not a bare array); each source is a `.aix` zip (Rust->WASM32 module + `Source.json` manifest + icon) — `installSource` downloads it and keeps only the extracted `.wasm` (base64, in `AidokuSource.wasmBytesBase64`). Manga-only. `AidokuSourceMethods` keeps one `AidokuWorker` per source (`AidokuWorker.dart`): a background isolate that owns the `AidokuRuntime` (`AidokuRuntime.dart`) so the interpreter never blocks the UI (a 500-chapter MangaDex feed takes about a minute in the debug interpreter); HTTP (`MClient`, cookies), `defaults` (`KvStore`) and logging are proxied back to the main isolate, results cross as JSON, and `PageUrl.process` calls back into the worker. Inside the worker: the `Engines/WasmEngine/WasmEngine.dart` (`package:wasd`) instance, the Postcard decode and the exported `get_search_manga_list`/`get_manga_update`/`get_page_list` calls, serialised per source. A source's `settings.json` defaults are extracted from the `.aix` at install (`AidokuDefaults.dart`, stored as `AidokuSource.defaults`; already-installed sources fetch them once on first use) and answer `defaults_get` until the user sets a value. `AidokuHost.dart` implements the resource-descriptor (`Rid`) host ABI the wasm exports call into - `net`, `html` (DOM via `package:html`; `AidokuSelector.dart` adds the SwiftSoup pseudo-selectors `:contains`/`:containsOwn`/`:has`/`:eq`; `parse_fragment` returns a document whose `<body>` holds the fragment, like SwiftSoup's `parseBodyFragment`), `std`/`env`, `defaults`; `js` runs `context_*` on QuickJS (`flutter_qjs`; the `webview_*` calls return errors); `canvas` is real on `package:image` (`AidokuImages.dart` images/blits, `AidokuPaths.dart` path fill/stroke/dash rasteriser and bitmap-font text; decode/encode go through `compute`, the only isolate use), and `net.get_image` + `process_page_image`/`get_image_request` run when a page carries context: `PageUrl.process` (not in JSON) is applied by the app's reader/downloader to the fetched bytes (Mangago unscramble). `parse_date` honours the Swift format/timezone (`AidokuDates.dart`), `sleep`/`set_rate_limit` are real, and `readBytes` copies out of wasm memory (a view was corrupting POST bodies). The `url` default comes from `source.json` `info.urls[0]`. `getPageList` passes the chapter exactly as `get_manga_update` returned it, with the manga it came from (tracked per chapter key). getPopular/getLatestUpdates use `get_manga_list` with a listing from `source.json`/`get_listings` picked by name (popular/latest patterns), else the `get_home` components (`AidokuHome.dart`), else `get_search_manga_list(null, page, [])`. Preferences: `getPreference`/`setPreference` are built from the `.aix` `settings.json` (stored in `defaults['__settings']`, `AidokuSettings.dart`): switch/select/segment/multi-select/text become `SourcePreference`s stored under `aidoku-<id>-pref-<key>` (the same keys `defaults_get` reads), a setting's `notification` calls `handle_notification`, and `basic` logins become username/password fields that call `handle_basic_login`. Not implemented: web logins (`handle_web_login` needs the app's web view), stepper/editable-list/button settings, `get_settings` (dynamic), filters UI (`filters.json`/`get_filters`), migration, deep links, alternate covers, number-typed defaults. Verified live against real community sources (Asura Scans, Mangakakalot) - `net`/`html`/Postcard decode all confirmed correct against actual responses. |
| **Shosetsu** | `ShosetsuExtensions` (Android) / `ShosetsuDesktopExtensions` (desktop) | Android + desktop | Independent backend for Shosetsu novel sources (`shosetsuorg/extensions`), Lua scripts. Unlike LNReader/Aidoku's Dart-side interpreter-in-an-isolate pattern, this backend vendors the real `shosetsuorg/kotlin-lib` engine (`app.shosetsu.lib`/`app.shosetsu.lib.lua`, GPLv3) — real LuaJ + OkHttp + Jsoup, the exact engine the upstream app runs scripts on — into a new `runtimeManager/shosetsu/` JVM module, reusing the same Android-in-process/desktop-sidecar plumbing as Aniyomi/CloudStream/Kotatsu rather than a new Dart interpreter. A repo is `index.json` (`{authors, libraries, scripts, styles, js}`, not a bare array — `RepoFormat.shosetsu` detection in `RepoGuard.dart` checks for the `scripts`+`libraries` keys); only `scripts` entries (`type: "LuaScript"`) become sources. `Source.repo` holds the repo *root* URL (e.g. `.../extensions/-/raw/dev/`), from which both the script URL (`<repo>src/<lang>/<fileName>.lua`) and the native side's `Require(name)` library lookups (`<repo>lib/<name>.lua`, resolved + cached by `ShosetsuExtensionManager` in `ShosetsuExtensionApi.kt`) are derived — a script's own embedded metadata header has no `repo`/`lang` field, so `ShosetsuRepoBackend.dart`'s `installSource` writes a `<id>.lua.meta.json` sidecar (`{repo, lang}`) next to each installed `<id>.lua` for the native side to read. `Novel.Chapter`/`Novel.Info` links are shrunk (`Extension.shrinkURL`) before crossing to Dart and expanded again before `parseNovel`/`getPassage`, matching the real app's URL-shortening convention. `Filter<*>` maps two ways depending on purpose: `searchFiltersModel` → `SourceFilter` JSON (search-time, round-tripped positionally since `SourceFilter` carries no id), `settingsModel` → `SourcePreference` JSON (persistent, keyed by `Filter.id.toString()`). Novel-only. Verified live end-to-end (install → popular → filters → search, including a `Require("novelvault")` multisrc-library dependency) against the real novelfull.com through the actual sidecar jar's stdin/stdout protocol. |

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
| `JavaEngine/` | Talk to a JVM that hosts Aniyomi/CloudStream desktop runtime. `JavaBridgeServer.dart` (localhost HTTP, port 4567 — Kotlin `Logger` and cookie callbacks post here; started on desktop *and* iOS), `JavaInstaller.dart`. Transports implement `Bridge/JavaBridge.dart` (`init(pluginJarPath:, libraryJarPaths:)`): `Bridge/SidecarBridge.dart` (one Java process per backend, desktop: `java -cp <desktopCore>:<plugin> Main`, or `-jar` for a self-contained plugin), `Bridge/EmbeddedJvmBridge.dart` (iOS — one embedded interpreter-only OpenJDK Zero VM via method channel `dartotsu_extension_bridge/embedded_jvm`; native side in `ios/`, Kotlin entrypoint `EmbeddedBridge` in `runtimeManager/libraries/commonDesktopLib`, and `runtimeManager/EMBEDDED_IOS_NOTES.md`). `Bridge/JavaBridgeFactory.dart` picks per platform. No jnigen/`package:jni`: an in-process JVM is one-per-process, so desktop uses sidecars. iOS runs the **same desktop plugin JARs** and core jar (no `-ios` variant; `DownloadablePlugin` picks the `desktopSplit` row; `EmbeddedJvmBridge` passes `core.jar:plugin.jar` as the one `jarPath` string and `EmbeddedBridge.load` splits it into one class loader per backend) — a source's `android.webkit.WebView` is the same everywhere: `FlutterWebViewProvider` (`commonDesktopLib/.../androidcompat/webkit/`, installed in `AndroidCompatModule.init`) drives a long-lived app WebView through the `wv*` calls of `Network/BridgeWebViewSessions.dart` (create / load / loadHtml / eval / interface / action / state / close, plus a long-polled event queue: page start / finish, progress, errors, every request the page makes through the `fetch` / XHR / resource-timing hooks, calls from `addJavascriptInterface` objects, which return a Promise). It does not intercept at the network layer, so `shouldInterceptRequest` only observes (its response is ignored) and `shouldOverrideUrlLoading` cannot cancel a navigation; cookies move through `WebViewCookieSync`; a session idle for 5 minutes is closed and recreated by the next call. There is no Chromium / JCEF any more (the old `KcefWebViewProvider` / `CefHelper` remain in the module but nothing creates them). iOS JVM logging: HotSpot output (`vfprintf`/`exit`/`abort` hooks), Java stdout/stderr (`EmbeddedBridge.installLogCapture` → `nativeLog`) and uncaught exceptions go to `Logger` as `[JVM] …` and to `bridge/logs/jvm.log` (rotated to `jvm.previous.log` each start); fatal reports land in `bridge/logs/hs_err.log` and are logged on the next start. |
| `TorrentEngine/` | libtorrent via `dart:ffi` (`ffi_bindings.dart`, `LibtorrentFlutter.dart` session + HTTP streaming server + tracker fetch, `LibTorrentAddon.dart` = the `Addon`, `Models.dart`). |
| `WasmEngine/WasmEngine.dart` | `WasmEngine` - thin wrapper around `package:wasd` (pure-Dart WebAssembly runtime, no native binaries). One instance per wasm module (own linear memory/state), unlike `JsEngineEnv`'s shared singleton. Used by Aidoku; `instantiate(bytes, imports)` requires every host import the module declares to be supplied by the caller. `call(name, args)` is async - host imports (e.g. Aidoku's `net`) may do real I/O, and wasd's interpreter transparently switches an export to its async invocation path if any host import it calls is async. |

### Player engine (`lib/Player/`, `lib/Engines/Mpv/`, `hook/`, `native/mpv/`, `third_party/media_kit_video`)

The video player is part of the bridge: what used to be `media_kit` (Predidit's fork) and `media_kit_video` was restructured into `lib/Player/`, barrel `lib/player.dart` (kept out of the main barrel because `Video` and a few other names clash with the bridge's own models; the player's `PlayerState` is `MpvPlayerState` for the same reason). `Engine/` is `Player` over `NativePlayer` (libmpv through ffi: `Core/` has the event loop, the library lookup and property helpers, `Utils/` the Android JNI helper), `Models/` the state, streams, tracks and `Media`, `Ffi/` media_kit's own utf8 / allocation helpers (Windows needs them), `Generated/Bindings.dart` the ffigen output, `Video/` the `VideoController` (`NativeVideoController` for desktop / macOS / iOS, `AndroidVideoController` for the Android surface), the `Video` widget, `SubtitleView` and the small fullscreen helpers (`Video/Fullscreen/`, what `VideoState.enterFullscreen` uses; the stock Material / Cupertino controls were dropped, the app draws its own). Removed from the original: web, OpenHarmony, the legacy aliases, the controls, the wakelock handling (the app owns it) and the `PlatformPlayer`-per-platform dispatch. Files in `lib/Player/` are PascalCase like the rest of the bridge (`NativePlayer.dart`, `Video/VideoController.dart`); the build hook's asset id `Player/Engine/Core/NativeEventLoopBindings.dart` must match the `@DefaultAsset` in that file, so rename both together. Each `NativePlayer` has its own operation lock (it was a static one, so a seek-preview or trailer player made the main player wait); only creating the libmpv handle shares a lock. Switching a track (`aid` / `sid` / `vid`) and adding an external one (`audio-add` / `sub-add`) are sent without waiting for mpv's reply (`wait: false` on `_setProperty` / `_command`), because mpv answers only after it re-seeks or opens the file, and the pending reply held the lock so pause, seek and play stalled behind it; the reply is still logged. `NativePlayer._handler` decodes an mpv event's property name once and switches on it, one small method per property (`_onTrackList`, `_onVideoParams`, `_onHook`, …); track and node-map parsing goes through `NativeNodeMap`. `PlayerConfiguration.observeStatistics` (default off) skips the bitrate, audio-parameter, audio-device and secondary-subtitle observers libmpv reports on every change. `VideoControllerConfiguration.fitRenderSize` (default on, `NativeVideoController`, i.e. Linux / Windows / macOS / iOS) makes the texture no larger than the `Video` widgets need: each `Video` reports its physical size and `fit` through `VideoController.reportViewSize`, the controller renders at the largest of those (`fittedRenderSize`, never above the video's own size, reductions under 15 % skipped, applied 250 ms after the last change so a window resize does not reallocate the three GL buffers on every frame) and calls the same `VideoOutputManager.SetSize` the video parameters use, so a 4K video in a 1080p window costs a quarter of the GPU work and memory; `setSize(width:, height:)` still pins an explicit size. The Linux render path (`third_party/media_kit_video/linux`) is a dedicated GL thread with an isolated EGL context and mailbox triple buffering over EGLImage with GPU-side fences, which was left as it is.

Native pieces: `hook/build.dart` (+ `hook/src`, `hook/native_bundles.json`) is the native-assets hook, now owned by this package: it puts libmpv (and on Android the JNI helper `libmediakitandroidhelper.so`) into the app from the prebuilt bundles and builds `native/mpv/*.c` (the event loop and the library-path lookup) as `dartotsu_mpv_loop`. `hooks.user_defines.dartotsu_extension_bridge.source` in the app's `pubspec.yaml` selects `bundled` (default), `external` (libmpv is not part of the app on Android, Linux and Windows, see below; macOS and iOS treat it as `bundled` because the Swift plugin links the XCFramework), `system` or `local`. The Android Java helper class `com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper` lives in `android/src/main/java` (the JNI library looks it up by that name) and `DartotsuExtensionBridgePlugin` hands it the application context (it no longer loads `libmpv` when the engine attaches, which would crash an app built with `external`). `third_party/media_kit_video` is the video output's native plugin only (textures, surfaces and the mpv render glue for Android, Linux, Windows, macOS and iOS), its `lib/` is empty on purpose.

`MpvAddon` (id `mpv`, shown as *Player*; only registered where `MpvAddon.downloadable`, i.e. not on iOS / macOS) downloads libmpv on first use: a per-ABI catalog (`_bundles`: Predidit's Android jars, Linux zips, Windows zip / 7z, the same builds and sha256 as `hook/native_bundles.json`, `test/mpv_catalog_test.dart` keeps both in step) is fetched with `Range` resume and three attempts, checked against its sha256, and only the library file is extracted into `bridge/mpv/<version>/` (zip through `archive`, the Windows x64 7z through `tar -xf`, which bsdtar on Windows 10+ reads). `received` / `total` / `progress` / `downloading` / `error` are observables, `cancel()` stops and removes the partial file, `checkForUpdate` compares the stored version with the catalog. `libraryPath` is `LIBMPV_LIBRARY_PATH` when set, else the downloaded file. `Mpv` (the static facade) owns the life cycle: `ensure()` downloads when needed and calls `MediaKit.ensureInitialized(libmpv: path)` (once per process), `ensureIfInstalled()` never downloads, `phase` / `error` / `speed` are observables for the app's UI. `test/player_playback_test.dart` plays a generated WAV through the real library (`LIBMPV_LIBRARY_PATH=… flutter test test/player_playback_test.dart`, Linux) and prints how long initialisation, `Player()` and the first duration take.

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

CloudStream desktop sidecar, end to end (`test/cloudstream_sidecar_test.dart`): starts the built jar with the bundled
JRE 21, copies the installed `.cs3` plugins into `$TMPDIR/dartotsu-cs-harness`, and checks that the list grows while
big plugins convert, that a refresh never unloads loaded plugins, that converted jars are reused on the next start,
that a call made mid-load waits for its provider, and that a multi-season show comes back grouped by season. It skips
itself when the jar, JRE or plugins are missing (`CS_JAR`, `CS_JAVA`, `CS_PLUGINS`, `CS_OFFLINE=1` override). If
Dartotsu is running (port 4567 is taken) the log based checks are skipped.

CloudStream desktop loader (`ExtensionLoader.desktop.kt`): plugins are prepared by a pool of background workers (half the cores, 2-8), the list call waits
at most 12 s and returns what is ready (the Dart side polls `pendingExtensions` and republishes the list), a refresh
only loads new/changed files and unloads removed ones (providers never disappear during one), `provider()` waits up to
3 minutes for a plugin that is still preparing, and the initial scan starts at `initializeDesktop` (`<data>/extensions/Anime`).
Converted jars carry a `<name>.jar.cv` stamp (hash of `BytecodeEditor`), so a plugin update of the sidecar no longer
rebuilds every cached jar. A show whose seasons restart their numbering is sent with the season in `scanlator`
(`Season N`, `Specials`) so the app's season chips apply.

CloudStream library: the plugin API (`com.lagradost.cloudstream3` MainAPI, extractors, `app`, utils, ...) is no longer hand-copied.
`syncCloudStreamLibrary` (`cloudStreamCommon/build.gradle.kts`) sparse-fetches `library/src` of `recloudstream/cloudstream` at the pinned
`upstreamSha` into `build/cloudstream-upstream` and adds `commonMain`, `jvmCommonMain` and `androidMain` as source dirs (desktop compiles the
androidMain actuals over the bridge's Android-compat layer). Bump the SHA to follow upstream; only app-side classes the library lacks
(`AppShims.kt`, `BridgeActivityShims.kt`: MainActivity/CommonActivity/UiText/ResultEpisode, `RepositoryManager`, plus `ExtensionLoader`) stay in the repo. `BytecodeEditor.restoreLocalClassOwner` puts the `EnclosingMethod` back on Kotlin local classes (`Outer$func$Local`) that dex dropped it from, otherwise kotlin-reflect (Jackson's Kotlin module) fails with "Unresolved class" (MegaProvider's `VerifiedRepo`). MegaProvider is a repository adder, not a source: it calls `RepositoryManager.addRepository`, which the bridge keeps in memory only.
`MDL_API_KEY` / `TRAKT_CLIENT_ID` in the generated `BuildConfig` are empty. Popular/latest call the provider's `getMainPage` (first/second
main page entry) and fall back to an empty search. The installed list is a change stream: the loader keeps one entry per plugin (`queued` / `converting` / `loading` / `failed` / `ready` with its sources / `removed`) with a version counter, `extensionChanges {since, waitMs}` long-polls for entries newer than `since` and `scanExtensions {path}` starts preparing new or changed files without waiting. The desktop Dart class (`_watch` / `_apply`) applies each entry to just that plugin's rows, in place (placeholder rows `Source.isPlaceholder`, id `loading:<path>`, with `installProgress` set while converting; a failed one keeps a delete button), so installing or deleting one plugin never reloads the others. Uninstall deletes the file, drops that plugin's rows locally and tells the runtime to unload it (desktop `scanExtensions`; Android's `refreshExtensions` is incremental too: only new/changed/removed plugins load or unload). Uninstall matches the plugin file by `sourcePlugin` (one plugin can register several providers).

CloudStream desktop jar from a terminal (loads every `.cs3` in a folder, prints how many loaded and which failed):

```
./runtimeManager/gradlew -p runtimeManager :cloudStream:cloudStreamDesktop:buildPlugin
python3 runtimeManager/scripts/cloudstream_test.py \
  runtimeManager/builds/desktopCore/desktopCore-plugin.jar:runtimeManager/builds/cloudStreamDesktop/cloudStreamDesktop-split.jar plugins/ \
  --repo https://raw.githubusercontent.com/phisher98/cloudstream-extensions-phisher/refs/heads/builds/repo.json
```

### Desktop core jar

The six desktop backends are **thin plugin jars on top of one shared `desktopCore` jar**
(`runtimeManager/libraries/desktopCore`, the shadow jar of `commonDesktopLib` and everything
it pulls in: kotlin, okhttp, jsoup, ICU, dex2jar, the Android compat layer, `Server`,
`ExtensionApi`). Before the split every plugin was a ~65 MB fat jar and 33,783 of ~34,000
entries were identical across them; now the core is ~65 MB once and a plugin is 0.7-14 MB
(aniyomi 0.7, tsundoku 0.9, kotatsu 1.4, shosetsu 3.6, ireader 7.5, cloudStream 14 - their
own libraries such as graalvm/luaj/guava stay in them). Android is unchanged (separate APKs).

- **Build.** Each `<backend>Desktop/build.gradle.kts` applies `desktop-plugin-build.gradle.kts`
  (publishes the excludes through `extra`, because shadow's types are not visible to an applied
  script) and configures its `shadowJar` to drop what the core already holds: a module the core
  resolves at the same version (`desktopCoreShared`) and any file entry the core jar contains
  (`desktopCoreEntry`, catches `files(...)` dependencies such as the Android jar; `META-INF` is
  left alone so `mergeServiceFiles` keeps the plugin's own service files). The build fails when a
  backend resolves a shared library at another version than the core (`desktopCoreCheck`), since
  the core is first on the classpath and would silently win. All shadow jars are reproducible, so
  an unchanged artifact keeps its hash, its version, and users don't re-download the core.
- **Index and older app builds.** Every desktop backend is published **twice** so no app build
  breaks: the self-contained jar older builds install (`<name>-plugin.jar`, `platform: desktop`,
  built by each project's `fatJar` task with the original configuration, same name, layout and
  version ledger as always, no `requires`) and the thin one (`<name>-split.jar`,
  `platform: desktopSplit`, `requires: {"desktopCore": <minimum versionCode>}`). `desktopCore` has
  no fat twin. A client picks its entry by `platform` (`desktop` before the split, `desktopSplit`
  now) and by `name`; the remote `fileName` is never read, only the local file name matters, so a
  new client keeps `<name>-plugin.jar` on disk: an old fat install counts as installed, and is
  replaced by the thin file because the index version is higher or, failing that, the file size
  differs from `fileSize`. With no `desktopSplit` entry (a custom index) a new client leaves what is
  installed alone and starts it with `-jar`. `prepare_release.py` versions both sets by file name
  (the split ledger starts at the fat one's), resolves `requires` and carries the unchanged ones
  over. Dropping the fat set later is one change: delete the `fatJar` tasks. Tested against the
  pre-split client code with the new index (it picks and installs the fat entries) and by
  `test/extensions/plugin_dependency_test.dart` (old install → split).
- **JVM addon.** `JvmAddon` (`Engines/JavaEngine/JvmAddon.dart`, id `jvm`, in `AddonManager`
  and so in Settings › Addons) owns both halves of the Java side: the Java runtime (a system
  Java 21+, else the bundled Temurin JRE `JavaRuntimeManager` downloads; desktop only, iOS runs an
  embedded VM) and the `desktopCore` jar. Its steps are `[jre, core]`; the JRE download reports
  bytes/speed and can be cancelled (`JavaRuntimeManager.cancel`). `uninstall()` stops every
  attached sidecar, then deletes the core and the bundled JRE.
- **Client.** `DesktopPlugin` (`Services/Shared/DesktopCorePlugin.dart`) lists `JvmAddon.instance`
  as its only dependency, so installing a desktop backend is **three steps: Java runtime → core →
  the backend**, and the core is updated first when the index has a newer one. Starting a backend
  (`DesktopJvmBackend.startRuntime`) calls `plugin.installDependencies()` (repairs a missing JRE or
  core, no update), `plugin.autoUpdate()` brings them current in the background, then it registers
  with the core (`attach(release:, reload:)`) and starts the sidecar with
  `libraryJarPaths: [core]`. A core update stops every attached sidecar first (the file is open in
  each; Windows can't replace it) and restarts them on the new file.
- **Tests.** `test/extensions/plugin_dependency_test.dart` and `test/engines/jvm_addon_test.dart`
  (local fake release server and a fake bundled Java: plans, step order and states, reuse, a newer
  core taken before the backend, a failing dependency, dependency-only updates, concurrent
  callers, offline, uninstall), and
  `test/engines/sidecar_split_classpath_test.dart` + `test/cloudstream_sidecar_test.dart` run the
  real sidecar on `core:plugin` (they skip when the jars/JRE are not there).

`runtimeManager/` (the JVM backend JARs, out of scope above) builds via
`./gradlew buildEverything` (desktop + android + the `embedded-bridge.jar`
shim). iOS uses the desktop JARs; after changing `EmbeddedBridge.kt`, copy the
rebuilt `embedded-bridge.jar` into
`ios/dartotsu_extension_bridge/Sources/dartotsu_embedded_jvm/Runtime/`. See
`runtimeManager/EMBEDDED_IOS_NOTES.md`.

`analysis_options.yaml` uses `flutter_lints`.
