# Kotatsu backend — status

Scope: `runtimeManager/kotatsu/**` and `lib/Services/Kotatsu/**`.

Ported from the user's fork
([`RyanYuuki/AnymeXExtensionRuntimeBridge`](https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge/tree/main/lib/Services/Kotatsu)),
adapted to this repo's `Extension` / `SourceMethods` / `Source` contracts (same
approach as Legado/LnReader, not a drop-in copy).

## Shape of the backend — one shared jar, not one-APK-per-source

Kotatsu ("Котацу") ships its parsers as **one jar bundling every source**
(`org.koitharu.kotatsu.parsers.*`, vendored under
`runtimeManager/kotatsu/kotatsuCommon`), unlike Aniyomi/CloudStream/Tsundoku/
IReader where each source is its own downloadable APK/JAR. Consequences:

- `KotatsuExtensions.addRepo` downloads a single `plugin.jar` per repo URL
  into `bridge/kotatsu/plugin.jar` — there is no per-source index to fetch.
- `getInstalledMangaExtensions` (native, `KotatsuExtensionApi` /
  `KotatsuExtensionLoader`) enumerates **every** parser in that jar,
  unfiltered.
- "Installing"/"uninstalling" a source doesn't download or delete anything —
  it just toggles that source's id in a `kotatsu_active_sources` KvStore
  list. `fetchMangaExtensions`/`fetchInstalledMangaExtensions` load the full
  set once and split it into `available`/`installed` by that allow-list.
- `detectUpdates` is a no-op and `updateSource` just re-fetches — there's
  nothing per-source to version-compare; the whole jar is one unit that gets
  replaced wholesale by re-running `addRepo`.
- Manga-only: `supportsAnime`/`supportsNovel` are `false`,
  `KotatsuSourceMethods.getVideoList`/`getNovelContent` are hard-stubbed
  (native `KotatsuExtensionApi` never implements them either — falls to the
  `ExtensionApi` interface defaults).

## Wired this pass

- `lib/Services/Kotatsu/Models/Source.dart` — `KotatsuSource extends Source`
  (`jarName`/`pkgName` on top of the base fields).
- `lib/Services/Kotatsu/KotatsuSourceMethods.dart` — thin
  `BridgeSourceMethods<KotatsuSource>` subclass.
- `lib/Services/Kotatsu/KotatsuExtensions.dart` — full `Extension`, following
  the shared-jar model above.
- `lib/ExtensionManager.dart` — registered under `Platform.isAndroid` only
  (see "Desktop — deliberately not wired" below).
- `android/src/main/kotlin/.../kotatsu/KotatsuBridge.kt` — new, mirrors
  `TsundokuBridge.kt`: registers the `kotatsuExtensionBridge` method channel
  against the generic `Handler` with `KotatsuExtensionApi` /
  `com.aayush262.dartotsu_extension_bridge.kotatsu_plugin` as the
  class/package to load via `loadPlugin`.
- `DartotsuExtensionBridgePlugin.kt` — registers/detaches `KotatsuBridge`
  alongside the other four.
- `runtimeManager/kotatsu/kotatsuCommon/.../KotatsuExtensionLoader.kt` — fixed
  a deprecated `Byte.toChar()` DEX-magic check (`bytes[0].toChar() != 'd'`) to
  `bytes[0].toInt() != 'd'.code` etc. Safe: DEX magic bytes are ASCII (`d`,
  `e`, `x`, `\n`), all < 0x80, so there's no sign-extension ambiguity between
  the two forms.
- `runtimeManager/kotatsu/kotatsuAndroid/build.gradle.kts` — `compileSdk`
  now reads `libs.versions.compileSdk` (was hardcoded `37`, inconsistent with
  every other plugin module) and `apply(from = "$rootDir/plugin-build.gradle.kts")`
  is uncommented, so `kotatsuAndroid` now participates in
  `./gradlew buildAllPlugins` / `printBuildVariants` like the other four
  ecosystems.
- `test/services/kotatsu_test.dart` — `KotatsuSource.fromJson`/`toJson`
  round-trip + id-coercion + missing-field tolerance (the only part of this
  backend that's testable without a platform channel or a real Android
  runtime).

Verified: `dart analyze lib test` clean, `flutter test` all green (65 tests),
`./gradlew :kotatsu:kotatsuCommon:compileKotlinDesktop` and
`:kotatsu:kotatsuDesktop:shadowJar` both `BUILD SUCCESSFUL`.

## Desktop — deliberately not wired

`kotatsuDesktop/build.gradle.kts` still has its `plugin-build.gradle.kts`
apply commented out, and `KotatsuExtensions` is only registered for
`Platform.isAndroid`. `KotatsuExtensionLoader`/`KotatsuExtensionApi` lean on
`dalvik.system.DexClassLoader`, `android.graphics.BitmapFactory`, and
`android.webkit.CookieManager` — real Android/Dalvik APIs, not something a
desktop JVM (even with the `AndroidCompat` shim used by the sidecar backends)
can satisfy. Unlike Aniyomi/CloudStream/IReader/Tsundoku, this isn't a
"needs a desktop entrypoint" gap — it's a different, Android-only plugin
loading mechanism, matching the AnymeX fork's own platform-channel-only
approach for this backend. `kotatsuCommon:compileKotlinDesktop` and
`kotatsuDesktop:shadowJar` both build (the module compiles against desktop
stubs), which says nothing about whether loading a real parsers jar through
`DexClassLoader` would work outside Android at runtime — it wouldn't, since
`DexClassLoader` itself is Android-only and unavailable on a desktop JVM
classpath.

## Not done / unverified

- No Android SDK or device in this environment — `kotatsuAndroid`'s Android
  target has not been compiled or run, and `KotatsuExtensionApi`'s
  `getInstalledMangaExtensions` has not been exercised against a real
  Kotatsu parsers jar.
- No `kotatsuAndroid-plugin.apk` has been built or published; `plugins.json`
  (wherever `DownloadablePlugin` releases are hosted) has no Kotatsu entry
  yet, so `KotatsuPlugin.autoUpdate()`/`isInstalled()` will report "not
  installed" until one is published.
- No live network smoke test against a real Kotatsu parsers-jar URL (same
  environment limitation as the Legado backend — outbound DNS/Cloudflare is
  blocked here).
