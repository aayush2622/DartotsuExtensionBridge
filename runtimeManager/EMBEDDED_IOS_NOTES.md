# iOS embedded-JVM support

On iOS the four `*Desktop` backends can't run as a `java -jar` subprocess and
can't JIT. Instead the plugin embeds an **interpreter-only OpenJDK Zero VM**
in-process (native side under `ios/`, Dart side
`lib/Engines/JavaEngine/Bridge/EmbeddedJvmBridge.dart`). The approach — a
static OpenJDK framework `dlopen`ed lazily, a dedicated JVM-sized bootstrap
thread, Serial GC, `-Xss8m` — is copied from
<https://github.com/kodjodevf/m_extension_server>. The transport stays the
repo's **stdio-sidecar JSON** shape (`{method,args}` → `{success,data|error}`),
not M-Extension-Server's NanoHTTPD loopback.

## Wired up

### Kotlin (`commonDesktopLib`)

- `Server.kt` — request dispatch extracted into `Server.handle(api, method,
  params)`; `Server.run` (the desktop stdio loop) is behaviourally unchanged.
- `EmbeddedBridge.kt` — `object` with `@JvmStatic` `load(jarPath)` /
  `call(jarPath, requestJson)` / `unload(jarPath)` / `pause()` / `resume()` /
  `isRunning()`. `load` attaches the backend fat JAR in a
  `ChildFirstURLClassLoader`, reflectively calls `Main.api()`, caches it.
  `call` runs `Server.handle(...)` and returns a
  `{"success":…,"data"|"error":…}` envelope. `pause`/`resume` keep loaded
  backends + source instances warm across an iOS background cycle (parity with
  M-Extension-Server's `EmbeddedBridge.pause`). The native layer
  (`ios/Classes/EmbeddedJvm.mm`) looks this class up as
  `com/aayush262/dartotsu_extension_bridge/EmbeddedBridge`.
- Each `*ExtensionCli.kt` `Main` has `@JvmStatic fun api(): ExtensionApi`
  (desktop `main` calls it too).

### Gradle — build variants (`./gradlew printBuildVariants`)

| command | output |
|---|---|
| `./gradlew buildAllPlugins` | desktop + android `builds/<p>/<p>-plugin.jar` |
| `./gradlew buildAllPlugins -PiosRuntime=true` | `builds/<p>/<p>-plugin-ios.jar` (Chromium/JOGL/JNA + native payloads stripped from the shadow JAR; `platform:"ios"` in the `.json`) |
| `./gradlew buildEmbeddedBridge` | `libraries/commonDesktopLib/build/libs/embedded-bridge.jar` — the slim JAR the embedded VM boots with (`EmbeddedBridge` + `Server` + `ChildFirstURLClassLoader` + `ExtensionApi` + gson + kotlin/coroutines; the dex2jar / JCEF / GraalVM / apk-parser / icu4j runtime is excluded) |
| `./gradlew buildEverything` | `buildAllPlugins` + `buildEmbeddedBridge` |

A single Gradle invocation only holds one value for the `iosRuntime` project
property, so the iOS JARs are a second run — same as M-Extension-Server's own
`-PiosRuntime=true`.

The `-PiosRuntime` excludes live in each `*Desktop/build.gradle.kts`
`tasks.shadowJar { if (iosRuntime) { … } }` block. If the tuning list needs to
change, change all four (they're identical).

## Still on you (needs macOS + a run of the Gradle build)

1. **Verify the iOS shadow JARs load under Zero.** The excludes make a
   *loadable* JAR — JCEF/CEF classes stay compiled in and only fault if a
   Cloudflare challenge actually reaches them. To make that path degrade
   cleanly instead of `NoClassDefFoundError`, guard the desktop
   `CloudflareInterceptor` / `KcefWebViewProvider` usage behind a capability
   check (M-Extension-Server does this in its `CloudflareInterceptor`).
2. **`DownloadablePlugin` platform filter.** CI (`build.yml`) now builds the
   iOS variants and `prepare_release.py` picks up `*-plugin-ios.json`, so
   `builds/plugins.json` gets a second row per backend
   (`{"name":"aniyomiDesktop","platform":"ios","fileName":
   "aniyomiDesktop-plugin-ios.jar", …}`). The Dart side still resolves plugin
   rows by `name` only — teach `DownloadablePlugin` to prefer the row whose
   `platform` matches (`ios` on iOS, `desktop` otherwise). `EmbeddedJvmBridge`
   then feeds that jar path to `load` / `call`.
3. **Publish `embedded-bridge.jar`** — CI stages it into
   `builds/embeddedBridge/` for the `latest` release. Fill `BRIDGE_JAR_URL` /
   `BRIDGE_JAR_SHA256` in `ios/PrepareEmbeddedRuntime.sh` to match, or commit
   the jar under `ios/Runtime/` and leave the download unused.
4. **Immutable iOS tags.** M-Extension-Server's rule: a changed iOS server JAR
   needs a fresh, immutable `ios-runtime-v*` tag + checksum (the `latest`
   rolling release is fine for desktop but not for something a pinned native
   build depends on).

## What was NOT synced from M-Extension-Server, and why

`M-Extension-Server` is one flat JVM-only `server` module (+ `AndroidCompat`)
with a NanoHTTPD loopback API. This repo's `runtimeManager` is a KMP
multi-ecosystem tree (aniyomi / cloudStream / iReader / tsundoku + shared
`libraries/`) with its own long-diverged copies of the extension-loading core.
`util/BytecodeEditor.kt` alone differs by ~1950 lines — this repo's is an
independent `asm.tree` + frame-analysis rewrite, not a stale copy of theirs.

A wholesale replacement of `BytecodeEditor` / `PackageTools` / the loader /
invoker with M-Extension-Server's would be a regression, not an update, and
can't be verified without the full Gradle + iOS toolchain. If you do want to
pull specific fixes across, the candidates are:

- `PackageTools.doTranslate(stream)` + `writeTranslatedClasses` (dedup on
  translated class names) instead of dex2jar `.to(path)`.
- The `LIB_VERSION_MIN/MAX` (1.3 / 1.5) + `EXTENSION_FEATURE` /
  `METADATA_SOURCE_*` constants and the lib-version gate.
- `ExtensionInstanceCache` / `MihonMetadataCache` shapes (per-source instance
  reuse, metadata memoisation).
- Their `CloudflareInterceptor` capability-gate (point 1 above).
- `AndroidCompat` module: diff `libraries/commonDesktopLib/src/main/java/
  xyz/nulldev/androidcompat/**` against their `AndroidCompat/src/main/java/**`.

Do those as individual, compile-checked commits — not in one blind pass.
