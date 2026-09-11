# iOS embedded-JVM support

On iOS the four `*Desktop` backends can't run as a `java -jar` subprocess and
can't JIT. Instead the plugin embeds an **interpreter-only OpenJDK Zero VM**
in-process (native side under `ios/`, Dart side
`lib/Engines/JavaEngine/Bridge/EmbeddedJvmBridge.dart`). The native boot
sequence — a static OpenJDK framework `dlopen`ed lazily, a dedicated
JVM-sized bootstrap thread, Serial GC, `-Xss8m` — is taken from
<https://github.com/kodjodevf/m_extension_server>. The transport stays the
repo's **stdio-sidecar JSON** shape (`{method,args}` → `{success,data|error}`),
not M-Extension-Server's NanoHTTPD loopback.

---

## How the JVM opens and loads on iOS — full step map

Mapped from `m_extension_server/ios/Classes/MihonEmbeddedBridge.mm` +
`.../PrepareEmbeddedRuntime.sh` + M-Extension-Server's `EmbeddedBridge.kt` /
`Main.kt`. Status is for **this repo's**
`ios/dartotsu_extension_bridge/Sources/dartotsu_extension_bridge/EmbeddedJvm.mm`
+ `EmbeddedBridge.kt` + `EmbeddedJvmBridge.dart`.

### Phase 0 — build / packaging (`ios/PrepareEmbeddedRuntime.sh`, runs as the pod `prepare_command`)

| # | m_extension_server step | here |
|---|---|---|
| 0.1 | download checksum-pinned `OpenJDK.xcframework.zip` (static libjvm + headers) and `java_bundle-device.zip` (java home: `lib/modules` JIMAGE, `conf`, `lib/security`, `tzdb.dat`) from the `embedded-openjdk-ios13-v16` release | ✅ same URLs / SHA-256 |
| 0.2 | `javac --patch-module java.logging=…` → `java-logging-shim.jar` (strips the JUL backend Zero can't load) | ✅ `RuntimeSources/ios_jul_shim/**` |
| 0.3 | `clang++ -dynamiclib -Wl,-all_load libdevice.a openjdk_runtime_exports.cpp … -lz -framework Foundation -framework CoreFoundation` → `OpenJDKRuntime.framework` (device); stub for simulator; `xcodebuild -create-xcframework` | ✅ verbatim |
| 0.4 | `openjdk_runtime_exports.cpp` re-exports the static VM's `loadfunctions()` as `MExtensionServerOpenJDKLoadFunctions` | ✅ same symbol name kept |
| 0.5 | stage `Runtime/`: their `MExtensionServer.jar` + `java-logging-shim.jar` + `lib/security/cacerts` + `release` | ⚠️ **ours stages `embedded-bridge.jar` instead of a server JAR** (`./gradlew buildEmbeddedBridge`). Publish + checksum still TODO (see below). |

### Phase 1 — trigger (Dart → method channel → Swift)

| # | m_extension_server | here |
|---|---|---|
| 1.1 | `MExtensionServer().startServer(port)` → channel `startServer` → `MExtensionServerPlugin.swift` | `EmbeddedJvmBridge.init()` → channel `dartotsu_extension_bridge/embedded_jvm` `start`, then `load {jarPath}` → `DartotsuExtensionBridgePlugin.swift` |
| 1.2 | Swift calls the C fn `MExtensionServerEmbeddedMihonStart(port, completion)` | `EmbeddedJvmStart(completion)` then `EmbeddedJvmLoad(jarPath, completion)` |
| 1.3 | app-lifecycle observers: bg → `…Pause`, active → `…Start` again | ✅ `applicationDidEnterBackground` → `EmbeddedJvmPause`, `applicationDidBecomeActive` → `EmbeddedJvmResume` |

### Phase 2 — the bootstrap thread (`EmbeddedJvm.mm`)

| # | m_extension_server | here |
|---|---|---|
| 2.1 | one dedicated `NSThread`, `stackSize = 8 MiB`, created via `dispatch_once`, a `NSCondition` block queue. Reason: Zero splits the native stack between the Java operand stack and C calls; a dispatch worker's small stack exhausts during `java.lang` bootstrap. | ✅ `DartotsuEmbeddedJvmThread`, identical |
| 2.2 | every op runs inside `@autoreleasepool` on that thread | ✅ `RunOnJvm` — used for `start` / `load` / `unload` / `pause` / `resume` |
| 2.3 | — | ➕ **`call` runs on a *concurrent* `dispatch_queue` instead**, attaching a fresh JNI thread per request (`AttachInvokeDetach`). The single bootstrap thread would serialize every request across all backends; M-Extension-Server gets concurrency from NanoHTTPD's worker pool. Same-source calls still serialize (`withSourceLock`). |

### Phase 3 — `CreateJavaVMIfNeeded` (first `start` only; `os_unfair_lock` guarded)

| # | m_extension_server | here |
|---|---|---|
| 3.1 | already-up path: verify cached class + method IDs, `AttachCurrentThread`, return | ✅ |
| 3.2 | `EmbeddedRuntimeResourcePath()` — `[NSBundle bundleForClass: NSClassFromString("<plugin>.<Plugin>")] pathForResource:@"<runtime>_bundle"`, fallback mainBundle | ✅ class `dartotsu_extension_bridge.DartotsuExtensionBridgePlugin`, bundle `dartotsu_extension_bridge_runtime` |
| 3.3 | `OpenJDKRuntimeHome()` = `<mainBundle>/Frameworks/OpenJDKRuntime.framework/lib` | ✅ identical |
| 3.4 | `VerifyRuntimeFiles`: `resourcePath` has `lib/security/cacerts`, `<serverjar>`, `java-logging-shim.jar`; `runtimeHome` has `lib/modules`, `conf/security/java.security`, `lib/tzdb.dat` | ✅ (checks `embedded-bridge.jar` in place of the server jar) |
| 3.5 | `LoadOpenJDKRuntime`: `dlopen(framework, RTLD_NOW\|RTLD_GLOBAL)` — GLOBAL required so the static VM resolves its JIMAGE/JDK natives via `dlsym(RTLD_DEFAULT,…)` | ✅ verbatim |
| 3.6 | probe required global symbols exist: `JDK_Canonicalize`, `JIMAGE_Open/Close/FindResource/GetResource`, `VerifyClassForMajorVersion` | ✅ verbatim |
| 3.7 | `dlsym(handle,"MExtensionServerOpenJDKLoadFunctions")` → `gLoadFunctions`; `dlsym(handle,"JNI_CreateJavaVM")` → `gCreateJavaVM` | ✅ same symbols |
| 3.8 | `CreateApplicationDirectory()` = `NSApplicationSupportDirectory/<AppName>Extensions` (created); temp dir = `NSTemporaryDirectory()/<AppName>Extensions` | ✅ `DartotsuExtensions` |
| 3.9 | JVM options: `-Djava.class.path=<serverjar>`, `-Xbootclasspath/a:<logging-shim>`, `-Djava.home=<runtimeHome>`, `-Djava.io.tmpdir`, `-Duser.home`, `-Djavax.net.ssl.trustStore[Password]`, `-Djava.awt.headless=true`, `-Dfile.encoding=UTF-8`, `-Djava.net.preferIPv4Stack=true`, `-Dorg.slf4j.simpleLogger.defaultLogLevel=warn`, `-XX:+UseSerialGC`, `-Xms128m -Xmx512m -XX:NewSize=64m -XX:MaxNewSize=256m`, `-Xss8m` | ✅ identical, except `-Djava.class.path` = `embedded-bridge.jar` (the shim, not a server jar) |
| 3.10 | comment: HotSpot must own SIGSEGV/SIGBUS while the VM runs — no app-level handler, and **no `-Xrs`** | ✅ same (no signal handler installed, no `-Xrs`) |
| 3.11 | `gLoadFunctions()` **before** `JNI_CreateJavaVM` (registers the static VM's natives) | ✅ |
| 3.12 | `gCreateJavaVM(&gJavaVM, &env, &args)`, check `JNI_OK` | ✅ |
| 3.13 | `CacheBridgeEntryPoints`: `FindClass("…/EmbeddedBridge")`, `NewGlobalRef`, `GetStaticMethodID` for the entry points | ✅ caches `load (String)V`, `call (String,String)String`, `unload (String)V`, `pause ()V`, `resume ()V` (theirs: `start (I,String)I`, `pause`, `stop`, `isRunning`) |

### Phase 4 — Kotlin side

| # | M-Extension-Server (`EmbeddedBridge.start` → `initApplication`) | here (`EmbeddedBridge.load` + first `call` = `initializeDesktop`) |
|---|---|---|
| 4.1 | `System.setProperty("ts.server.rootDir", appDir)` | n/a — each backend's data root arrives via the `initializeDesktop` RPC path (`CommonDesktopApi.rootDir`), Dart-chosen |
| 4.2 | `CookieHandler.setDefault(CookieManager())` | ✅ done per-backend inside `NetworkHelper` (aniyomi) etc. ⚠️ process-global: last backend to init wins `CookieHandler.getDefault()`. Acceptable; a true fix is per-backend cookie stores. |
| 4.3 | `startMainLooper()` — daemon thread: `Looper.prepareMainLooper(); Looper.loop()` | ✅ each backend's `PlatformInit.initializeDesktop` starts a `Looper` thread (⚠️ **not marked daemon** — see gaps) |
| 4.4 | `DI.global.addImport(ConfigKodeinModule…)`, `AndroidCompatInitializer().init()`, `androidCompat.startApp(App())` | ✅ per-backend `startKoin { … androidCompatModule(root) … }` + `context.onCreate()` |
| 4.5 | one shared `MExtensionServerController` (NanoHTTPD) for all sources | ➕ **each backend JAR loaded in its own `URLClassLoader` parented to `ClassLoader.getPlatformClassLoader()`** (JDK only). Every backend gets its own Koin `GlobalContext` / Injekt / `Looper` / caches — same isolation the separate desktop processes have. Nothing crosses the shim↔backend boundary but `java.lang.String`, so there is no shared-coroutine-runtime / shared-gson hazard. |
| 4.6 | request → NanoHTTPD `/dalvik` → `DalvikHandler` → source method | `EmbeddedBridge.call` sets TCCL = backend loader, reflects into `Main.handle(requestJson)` → `Server.handleEmbedded` → `runBlocking { withSourceLock { Server.handle(api, method, params) } }` — all in the backend's own class loader |

### Phase 5 — lifecycle

| # | M-Extension-Server | here |
|---|---|---|
| 5.1 | bg → `EmbeddedBridge.pause()` → stop NanoHTTPD listener, keep loaded instances | `EmbeddedBridge.pause()` — no listener to stop; loaded backends + source instances kept warm (same end state) |
| 5.2 | active → recreate controller (VM already up) | `EmbeddedBridge.resume()` — no-op; VM + backends already warm |
| 5.3 | `stop()` → `MExtensionServerLoader.cleanupTempFiles()` | ⚠️ **no global stop / temp cleanup** — `unload(jarPath)` drops one backend's loader; the VM never exits on iOS so nothing runs the desktop shutdown hook. |

---

## Fix that was required for the child-loader design (found by testing on Linux)

`PackageTools.loadExtensionSources` loads each extension source JAR through
`commonDesktopLib`'s `ChildFirstURLClassLoader`, which delegated
non-extension classes (`eu.kanade.tachiyomi.*`, okhttp, `android.*`) to
**`ClassLoader.getSystemClassLoader()`**. On desktop (`java -jar`) the system
loader *is* the backend runtime, so that works. Under the embedded VM the
system class path is only the tiny `embedded-bridge.jar`, so every extension
load failed with `ClassNotFoundException` and `getInstalledMangaExtensions`
returned `[]`.

Fix (`ChildFirstURLClassLoader.kt`): delegate to
`ChildFirstURLClassLoader::class.java.classLoader` instead — the loader that
actually holds the runtime. On desktop that is the system loader (no-op); under
the embedded VM it is `EmbeddedBridge`'s per-backend `URLClassLoader`.

## Verified on Linux (`java -XX:+UseSerialGC -cp embedded-bridge.jar Harness aniyomiDesktop-all.jar ~/Documents/Dartotsu/bridge/aniyomi`)

The harness mimics the native side (reflect `EmbeddedBridge.load` / `.call`):

- `load` 60 ms; `initializeDesktop` → `{"success":true}` — Koin + AndroidCompat + Looper up
- `getInstalledMangaExtensions` → full list (Comix, Mangakakalot, Mangadotnet, …) — APK→JAR (dex2jar, `BytecodeEditor`, `PackageTools`), icon extraction, source instantiation all identical to the sidecar
- `getPopular` reaches the real okhttp interceptor chain (fails only on the
  external `localhost:8191` Cloudflare resolver — the desktop sidecar fails
  identically without FlareSolverr running)
- two overlapping calls to one source (`getPopular` + `getLatestUpdates`) both
  returned clean envelopes — `withSourceLock` serialized them, no corruption

## Build variants (`./gradlew printBuildVariants`)

| command | output |
|---|---|
| `./gradlew buildAllPlugins` | desktop + android `builds/<p>/<p>-plugin.jar` |
| `./gradlew buildAllPlugins -PiosRuntime=true` | `builds/<p>/<p>-plugin-ios.jar` — Chromium/JOGL/JNA + native payloads stripped; `platform:"ios"` in the `.json` |
| `./gradlew buildEmbeddedBridge` | `libraries/commonDesktopLib/build/libs/embedded-bridge.jar` — ONLY `EmbeddedBridge` + kotlin-stdlib (~6.5 MB). Its sole job is to `URLClassLoader` each backend JAR and reflect into `Main.handle`; needs no gson/coroutines/Server/ExtensionApi. |
| `./gradlew buildEverything` | `buildAllPlugins` + `buildEmbeddedBridge` |

## Swift Package Manager support

Flutter plugin sources/resources moved from `ios/Classes/` + `ios/Resources/`
to `ios/dartotsu_extension_bridge/Sources/dartotsu_extension_bridge/` (+
`include/dartotsu_extension_bridge/` for the public header), matching
Flutter's [SPM plugin layout](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors).
`ios/dartotsu_extension_bridge/Package.swift` declares the same sources, a
`.copy("Runtime")` resource matching the podspec's `dartotsu_extension_bridge_runtime`
bundle, and an `OpenJDKRuntime` `binaryTarget` pointing at the same
`Frameworks/OpenJDKRuntime.xcframework` the podspec vendors. The podspec
still works unchanged (paths updated to match) and both build systems read
the exact same files that `PrepareEmbeddedRuntime.sh` generates.

**Real risk, unverified (no macOS here):** `PrepareEmbeddedRuntime.sh` only
runs automatically as CocoaPods' `prepare_command` — SPM has no equivalent
hook for a `.buildTool()` plugin (Xcode sandboxes those with no network
access), so the `binaryTarget`'s local `path:` and the `Runtime` resource
won't exist until something has run that script. In today's mixed setup
(flutter_qjs / install_plugin / isar_community_flutter_libs don't support
SPM yet) CocoaPods still runs for the whole app regardless, so
`prepare_command` keeps populating these files as a side effect — but
whether Xcode resolves the SPM package graph *before* `pod install` has run
in a given build, and whether that ordering matters, is unverified. If it
ever does block a build: this is the same shape of problem
`embedded-bridge.jar` had (`Still on you` #4/#5 below) — the durable fix is
publishing a pinned, checksummed `OpenJDKRuntime.xcframework` release zip
and switching the `binaryTarget` to `url:`/`checksum:` (see
`media_kit_libs_ios_video`'s `Package.swift` for the pattern: SPM downloads
remote binary targets during package *resolution*, which does have network
access, unlike build-tool plugins), instead of the local `path:` this
commit uses.

`Package.swift` checks for `Frameworks/OpenJDKRuntime.xcframework` up front
(`FileManager.fileExists`) and writes a clear `FileHandle.standardError`
diagnostic if it's missing, instead of letting SPM fail with an opaque
"binary target not found" — same techniques (`FileManager` checks and
stderr diagnostics run directly in the manifest) as `media_kit_video`'s and
`permission_handler_apple`'s real, published `Package.swift` files. Cross-
checked several other real plugins already in this machine's pub cache
before writing any of this: `firebase_crashlytics` needs an Xcode
build-phase script injection under CocoaPods (`crashlytics_add_upload_symbols`)
that it simply **doesn't replicate** under SPM at all — confirming that
even Google's own Firebase plugins accept "this doesn't fully port to SPM
automatically" for prepare_command-shaped problems, rather than inventing an
unverified plugin-based workaround.

## Still on you (needs macOS / an on-device run)

1. **`CloudflareInterceptor` degrade path.** The `-PiosRuntime` shadow drops
   JCEF but the classes stay compiled in; a CF challenge on iOS hits
   `localhost:8191` and fails (as seen in the Linux test). Guard it behind a
   capability check that returns "unsupported" instead — M-Extension-Server
   does this in its `CloudflareInterceptor`.
2. **Daemon-flag the `Looper` thread** in each `*ExtensionApi.desktop.kt`
   `PlatformInit.initializeDesktop` (`isDaemon = true`). Harmless on desktop
   (process exits anyway); on iOS the VM is shared and long-lived so a
   non-daemon looper per backend is a leak.
3. **`DownloadablePlugin` platform filter.** CI now builds `*-plugin-ios.jar`
   and `prepare_release.py` emits an `ios` row per backend in
   `builds/plugins.json`. Teach the Dart `DownloadablePlugin` to pick the row
   whose `platform` matches (`ios` on iOS).
4. ~~**Publish `embedded-bridge.jar`**~~ — done: CI's `build` job already
   stages it into every `latest` release (confirmed live at
   `.../releases/download/latest/embedded-bridge.jar`).
   `BRIDGE_JAR_URL`/`BRIDGE_JAR_SHA256` in `ios/PrepareEmbeddedRuntime.sh`
   now point at and pin that real file. Still open: see #5.
5. **Immutable iOS tags** — `latest` is a rolling tag (deleted + recreated
   every CI run), so the pinned `BRIDGE_JAR_SHA256` above goes stale
   whenever `embedded-bridge.jar`'s contents change (re-download + re-hash
   it, same as any other pinned artifact here). A changed iOS JAR should
   really get a fresh immutable `ios-runtime-v*` tag + checksum instead, so
   this stops needing manual re-pinning — not done.
6. **First-call init race (pre-existing).** `PlatformInit.initializeDesktop`
   guards with `if (GlobalContext.getOrNull() != null) return`, not a
   `@Volatile` + `synchronized` block like M-Extension-Server's
   `initApplication`. The sidecar `run()` and the embedded `call` queue both
   fan requests out concurrently, so a request that races the very first
   `initializeDesktop` can hit `KoinApplication has not been started`. The
   Dartotsu app avoids it by `await`ing `initializeDesktop` before any other
   call (verified). A belt-and-braces fix is to make `PlatformInit` init
   idempotent under a lock.

## What was NOT synced from M-Extension-Server, and why

`M-Extension-Server` is one flat JVM-only `server` module (+ `AndroidCompat`)
with a NanoHTTPD loopback API. `runtimeManager` is a KMP multi-ecosystem tree
with its own long-diverged extension-loading core — `util/BytecodeEditor.kt`
alone differs by ~1950 lines (an independent `asm.tree` + frame-analysis
rewrite, not a stale copy). A wholesale swap would be a regression. Specific
fixes worth cherry-picking as individual compile-checked commits:

- `PackageTools`: `doTranslate(stream)` + `writeTranslatedClasses` (dedup on
  translated class names) instead of dex2jar `.to(path)`.
- `ExtensionInstanceCache` per-instance invocation lock — partly covered now by
  `Server.withSourceLock`; theirs also keys the source *instance*.
- `MihonMetadataCache` — round-trips TachiyomiX 1.6 `SManga.memo` /
  `SChapter.memo` across the stateless RPCs (only relevant once the protocol /
  models carry `memo`).
- `Extension.extractAssetsFromApk` shape (asset + `.properties` handling).
