# Kotatsu backend — status

Scope: `runtimeManager/kotatsu/**` and `lib/Services/Kotatsu/**`.

Ported from the user's fork
([`RyanYuuki/AnymeXExtensionRuntimeBridge`](https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge/tree/main/lib/Services/Kotatsu)),
adapted to this repo's `Extension` / `SourceMethods` / `Source` contracts (same
approach as Legado/LnReader, not a drop-in copy), then extended to Android +
Desktop to match how every other dual-platform backend here (Aniyomi,
CloudStream, IReader, Tsundoku) is shaped.

## Shape of the backend — one shared jar, not one-APK-per-source

Kotatsu ("Котацу") ships its parsers as **one jar bundling every source**
(`org.koitharu.kotatsu.parsers.*`, vendored under
`runtimeManager/kotatsu/kotatsuCommon`), unlike Aniyomi/CloudStream/Tsundoku/
IReader where each source is its own downloadable APK/JAR. Consequences,
identical on both platforms:

- `addRepo` downloads a single `plugin.jar` per repo URL — there is no
  per-source index to fetch.
- `getInstalledMangaExtensions` (native) enumerates **every** parser in that
  jar, unfiltered.
- "Installing"/"uninstalling" a source doesn't download or delete anything —
  it just toggles that source's id in a `kotatsu_active_sources[_desktop]`
  KvStore list. `fetchMangaExtensions`/`fetchInstalledMangaExtensions` load
  the full set once and split it into `available`/`installed` by that
  allow-list.
- `detectUpdates` is a no-op and `updateSource` just re-fetches — there's
  nothing per-source to version-compare; the whole jar is one unit that gets
  replaced wholesale by re-running `addRepo`.
- Manga-only: `supportsAnime`/`supportsNovel` are `false`,
  `KotatsuSourceMethods.getVideoList`/`getNovelContent` are hard-stubbed
  (native `KotatsuExtensionApi` never implements them either — falls to the
  `ExtensionApi` interface defaults).

## Dart layer — Android + Desktop, matching sibling backends' file layout

- `lib/Services/Kotatsu/KotatsuSourceMethods.dart` — shared
  `BridgeSourceMethods<T>` subclass, bridge-agnostic (works over
  `MethodChannelBridge` on Android and `JniExtensionBridge` on desktop
  unchanged, same as `CloudStreamSourceMethods`/`TsundokuSourceMethods`).
- `lib/Services/Kotatsu/KotatsuAndroid/KotatsuExtensions.dart` +
  `Models/Source.dart` (`KotatsuSource`) — Android, via
  `MethodChannelBridge` / `MethodChannel('kotatsuExtensionBridge')`.
- `lib/Services/Kotatsu/KotatsuDesktop/KotatsuDesktopExtensions.dart` +
  `Models/Source.dart` (`KotatsuDesktopSource`) — desktop, via
  `JniExtensionBridge`/`JavaBridge` (JNI in-process or sidecar, whichever
  `createJavaBridge()` picks), same shape as
  `CloudStreamDesktopExtensions`/`TsundokuDesktopExtensions`.
- `lib/ExtensionManager.dart` — `KotatsuExtensions()` under
  `Platform.isAndroid`, `KotatsuDesktopExtensions()` under `_jvmBackends`
  (Windows/Linux/macOS/iOS-embedded-JVM), exactly like the other four.
- `android/src/main/kotlin/.../kotatsu/KotatsuBridge.kt` — mirrors
  `TsundokuBridge.kt`: registers the `kotatsuExtensionBridge` method channel
  against the generic `Handler` with `KotatsuExtensionApi` /
  `com.aayush262.dartotsu_extension_bridge.kotatsu_plugin` as the
  class/package to load via `loadPlugin`. Wired into
  `DartotsuExtensionBridgePlugin.kt` alongside the other four.
- `test/services/kotatsu_test.dart` — `KotatsuSource`/`KotatsuDesktopSource`
  `fromJson`/`toJson` round-trip + id-coercion + missing-field tolerance
  (the only part of this backend testable without a platform channel or a
  real runtime).

## Native layer — where Android and Desktop actually differ

`KotatsuExtensionApi.kt` (commonMain) is a straightforward `expect`/`actual`
`PlatformInit` dispatcher that was already correctly platform-split. The one
piece that *wasn't* — and is the reason "desktop" didn't actually work
before this pass despite `kotatsuDesktop:shadowJar` happily compiling — was
`KotatsuExtensionLoader`. It used to live directly in `commonMain` and pull
in `android.content.Context`, `android.graphics.BitmapFactory`,
`android.webkit.CookieManager`, and `dalvik.system.DexClassLoader`. It
*compiled* for desktop too, because `commonMain` gets an `android-jar` compile
stub + the `androidcompat` runtime shim on that target — but `DexClassLoader`
itself has no real backing implementation on a plain JVM (it needs a genuine
Dalvik/ART runtime to interpret DEX bytecode), so it would have thrown at the
first `getInstalledMangaExtensions` call, not at compile time.

Fixed by turning `KotatsuExtensionLoader` into a proper `expect object` in
`commonMain` with two real `actual` implementations:

- **`androidMain/.../KotatsuExtensionLoader.kt`** — the original
  DexClassLoader-based implementation, moved here unchanged (plus the
  `Byte.toChar()` → `.toInt()`/`.code` DEX-magic fix from the previous pass:
  safe, since DEX magic bytes are ASCII and all `< 0x80`). Also revealed a
  second pre-existing, unrelated bug while getting this to actually compile
  for the first time: `kotatsuCommon`'s `androidMain` dependency block was
  missing `uy.kohesive.injekt:injekt-core` entirely (present via
  `commonDesktopLib`'s desktop-only Injekt-compatible shim, never added for
  the real Android target) — added directly in `kotatsuCommon/build.gradle.kts`.
- **`desktopMain/.../KotatsuExtensionLoader.kt`** (new) — runs the jar's
  `classes.dex` through the *same* `PackageTools.dex2jar` conversion the
  other four JVM-sidecar backends already use for their APKs, then loads
  the converted jar with `PackageTools.getClassLoader` (a plain, parent-first
  `URLClassLoader`). Because `kotatsuCommon` already vendors the full
  `org.koitharu.kotatsu.parsers.*` model/interface classes on desktop's own
  classpath, parent-first delegation means those classes resolve to the
  *same* `Class` objects inside and outside the plugin jar — so a loaded
  parser can be used as a real `MangaParser` directly (`is`/`as` and normal
  method calls), unlike Android's `KotatsuMangaParserWrapper`, which exists
  only because `KotatsuAndroidPluginClassLoader` is a *child-first* loader
  that deliberately keeps those same classes isolated per plugin jar. A
  `DesktopMangaLoaderContext` fills in the platform-specific pieces
  (`java.awt.image.BufferedImage` for `Bitmap`/image descrambling instead of
  `android.graphics.Bitmap`, an in-memory `CookieJar` instead of
  `android.webkit.CookieManager`).
- `kotatsu/kotatsuDesktop/build.gradle.kts` — `plugin-build.gradle.kts` apply
  uncommented, same as `kotatsuAndroid`'s from the previous pass; both now
  participate in `buildAllPlugins`/`printBuildVariants`. Also added the
  `-PiosRuntime=true` JCEF/JOGL/JNA exclude block (same as the other four
  Desktop modules) — cuts the shadow jar from ~64 MB to ~39 MB.
- **`desktopMain/.../KotatsuExtensionCli.kt`** (new) — the piece that made
  the first version of this pass non-functional despite every build
  succeeding: `kotatsuDesktop`'s shadow jar manifest has always pointed
  `Main-Class` at `com.aayush262.dartotsu_extension_bridge.Main`, but no
  such class existed anywhere in the module. `SidecarBridge` runs
  `java -jar <pluginJar>` directly — that's a hard failure at process
  start, not something a `shadowJar`/`buildPlugin` task would ever catch,
  since Gradle doesn't verify a manifest's `Main-Class` points at a real
  class. `EmbeddedJvmBridge` (iOS) would have hit the same gap the other
  way, reflecting for a `Main.handle(String):String` that didn't exist.
  Added the same `object Main { api(); main(args); handle(requestJson) }`
  shape every other backend has (`TsundokuExtensionCli.kt` etc.), wired to
  `KotatsuExtensionApi`.

## Verified

- `dart analyze lib test` clean; `flutter test` 67/67 green.
- `./gradlew :kotatsu:kotatsuCommon:compileAndroidMain` — **BUILD SUCCESSFUL**
  (this is the first time this target has actually been compiled; an Android
  SDK is present in this environment after all).
- `./gradlew :kotatsu:kotatsuAndroid:assembleDebug` — **BUILD SUCCESSFUL**,
  produces a real debug APK.
- `./gradlew :kotatsu:kotatsuCommon:compileKotlinDesktop` — **BUILD
  SUCCESSFUL**, both with and without `-PiosRuntime=true`.
- `./gradlew :kotatsu:kotatsuAndroid:buildPlugin :kotatsu:kotatsuDesktop:buildPlugin`
  — **BUILD SUCCESSFUL**, produces
  `builds/kotatsuAndroid/kotatsuAndroid-plugin.apk` +
  `builds/kotatsuDesktop/kotatsuDesktop-plugin.jar` with matching
  `-plugin.json` metadata, same shape as every other ecosystem.
- **Actual runtime smoke test**, not just a build: ran
  `java -jar kotatsuDesktop-all.jar` directly and drove it over stdin with
  the real sidecar JSON protocol —
  `{"method":"initializeDesktop",...}` → `{"success":true}` and
  `{"method":"getInstalledMangaExtensions",...}` → `[]` (against an empty
  scratch directory, so an empty list is the correct answer), with the
  loader's own `[Kotatsu-Desktop] Scan complete. Found 0 sources.` log line
  showing up — proof the `Main` entrypoint, the stdio protocol, and the new
  `desktopMain` loader code all actually run, not just compile.

## Not done / unverified

- No real Kotatsu parsers jar was available to test against, on either
  platform, so the smoke test above only exercises the "no jar present"
  path. `getInstalledMangaExtensions`/`getPopular`/etc. compile and now run
  without crashing, and the reasoning about parent-first vs. child-first
  classloading is sound, but end-to-end behavior against an actual jar
  (does the jar really ship `classes.dex`, do parser constructors really
  take a bare `MangaLoaderContext`, etc.) is unverified. Same environment
  limitation that blocked a live smoke test for Legado (outbound
  DNS/Cloudflare is blocked here).
- Neither plugin has been published; `plugins.json` (wherever
  `DownloadablePlugin` releases are hosted) has no Kotatsu entry yet, so
  `KotatsuPlugin`/`KotatsuDesktopPlugin.autoUpdate()`/`isInstalled()` will
  report "not installed" until one is.
- iOS runs `KotatsuDesktopExtensions` through the embedded-JVM path along
  with the other four sidecar backends (`_jvmBackends` includes
  `Platform.isIOS`); whether dex2jar + the embedded interpreter-only OpenJDK
  Zero VM actually handles a real Kotatsu jar is unverified, same as it is
  for the other four there.
