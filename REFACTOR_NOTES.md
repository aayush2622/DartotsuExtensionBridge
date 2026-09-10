# Dart refactor — session notes

Branch: **`refactor/dart-cleanup`** (plugin) + **`test/extension-bridge-models`** (Dartotsu-rewrite-re app).
Nothing pushed. Every commit below was verified with `dart analyze` (plugin) and,
for the behavioural ones, `flutter analyze` + `flutter test` + `flutter build linux --debug`
against the app at `../Dartotsu-rewrite-re`.

## Commits (oldest → newest)

| Commit | What |
|---|---|
| `fix: restore flutter dependency and clear analyzer warnings` | Uncommented the `flutter` SDK dep (code imports `package:flutter/*` everywhere); removed 3 dead members the analyzer flagged. |
| `refactor: delete unreferenced dead code` | Deleted `Extensions/PluginManager.dart` and `Services/Mangayomi/Eval/JavaScript/` (both unreferenced; the latter an abandoned 3rd `JsExtensionEngine`). |
| `refactor: unify LnReader service directory casing` | Merged `Services/Lnreader/` + `Services/LnReader/` into one dir. |
| `refactor: small correctness/readability fixes in core` | `BridgeSourceMethods.isAnime` → `itemType == ItemType.anime` (was magic `index == 1`); `setVal` drops dead `async`/try-catch, gains a real `catchError`. |
| `docs: correct CLAUDE.md to match the tree` | ItemType order, the two `ExtensionBridge.dart` files, dropped-code refs. |
| `style: apply dart format to lib` | Formatting only, 33 files, generated `.g.dart` excluded. |
| `refactor: extract shared Tachiyomi repo index parsing` | New `Services/Shared/TachiyomiRepo.dart`: `tachiyomiFallbackRepoUrl` (was duplicated 5× verbatim), `tachiyomiIndexUrl`, generic compute-safe `parseTachiyomiRepoIndex<T>`. **Bug fixed:** name-prefix strip used a hand-counted offset — IReader dropped the first char of every extension name, Aniyomi/Tachiyomi left a leading space. Now strips `prefix.length`. |
| `test: add plugin unit tests for models and the Tachiyomi repo helpers` | New `test/` tree, 23 tests. Shared parser error log switched `Logger.log` → `debugPrint` (runs in `compute()`). |
| `refactor: PackagedSource base + shared detectUpdates` | `Services/Shared/PackagedSource.dart` holds `pkgName`/`apkName` for all 6 `*Source` subtypes; identical `detectUpdates` in 5 of them collapses to `detectTachiyomiUpdates(this, …)`. IReader-desktop keeps its own (copies extra fields). |
| `chore: drop no-op cache remove in quarkuc getShareToken` | `shareTokenCache.remove(x)` inside `if (!containsKey(x))` — provably a no-op. |
| `docs: …` (this file + CLAUDE.md) | |

Net: roughly **-450 lines** in `lib/`, +2 shared files, +2 test files.

## Behavioural changes to sanity-check in the app

1. **Extension display names (Aniyomi / IReader / Tsundoku repos).**
   The prefix (`"Aniyomi: "`, `"ireader: "`, …) is now stripped by its real
   length. Expected: IReader names show their full first character again;
   Aniyomi "Tachiyomi: X" entries lose a stray leading space. IDs unchanged.
2. **`detectUpdates`** for those backends now runs through one shared function.
   Logic is identical to the old per-class copies (version compare → copy
   `apkName`/`iconUrl`/`versionLast`, set `hasUpdate`). Worth confirming the
   "update available" badge still appears for an outdated installed extension.
3. **`flutter` dep in `pubspec.yaml`** — confirm `flutter pub get` still
   resolves in the app (it did here).

Everything else (dead-code deletion, dir rename, formatting, model base class)
is type-/compile-level and covered by the analyzer + build.

## Not done (deliberately)

- `addRepo` / `fetchRepo` / `_loadInstalled` / `installSource` / `uninstallSource`
  are still duplicated across the backend pairs. They have enough per-backend
  variation (APK install vs file+JNI, private-dir handling) that a blind merge
  risked runtime breakage I can't detect without a device. Left for a review
  pass with the app in hand.
- `lib/ExtensionBridge.dart` (the `DartotsuExtensionBridge` class) vs
  `lib/Extensions/ExtensionBridge.dart` (the transport) — confusing same-name
  pair. The app deep-imports the former, so renaming needs a coordinated app
  change; skipped.
- `*Source.apkUrl` is a computed getter in 4 subtypes and a stored field in 2
  (ISource/IdSource) — not unified.

## Test status

- Plugin: `flutter test` → 23 pass (`test/models/`, `test/services/`).
- App: `flutter test` → 12 pass (`test/dartotsu_extension_bridge_models_test.dart`);
  the stale default `widget_test.dart` was removed (it didn't compile).
- App: `flutter build linux --debug` → OK.

---

## Install / update / delete bug-fix pass

Went through every backend's `installSource` / `updateSource` / `uninstallSource`
plus `DownloadablePlugin` and `detectUpdates`.

### Crash / total-breakage fixes

- **IReader Android install was dead for `index.min.json` repos.** The shared
  `parseTachiyomiRepoIndex` never populated `TachiyomiRepoEntry.apkUrl` (only the
  `.pb` path did), and `ISource` *stores* `apkUrl` as a plain field rather than
  deriving it, so `installSource` always threw "Source APK URL is required".
  Fixed by deriving `apkUrl` (`<repo>/apk/<file>`) in the JSON parser — every
  backend now gets a non-null `apkUrl` / `apkUrlOverride`.
- **Desktop `installSource` (Aniyomi/Tsundoku/IReader/CloudStream) never checked
  the HTTP status.** A 404 / 500 / Cloudflare HTML page was written straight out
  as the `.jar`, then the JVM failed to load it with an opaque error. All four
  now go through `downloadPackageFile()` — status check, streamed to `.tmp`,
  atomic rename, so an interrupted download can't leave a half-written archive
  in the extensions dir.
- **`uninstallSource` force-unwrapped `s.apkPath!`** on every desktop backend and
  IReader Android — null for any source whose native metadata lacked it →
  crash. Now falls back to `apkName` / a derived name.
- **Aniyomi & Tsundoku Android `uninstallSource` dereferenced `s.apkUrl!`** at
  the top of the method (before the `try`) — null for an installed source with
  no stored override → the whole uninstall threw before doing anything. Now
  resolves the package name null-safely.
- **CloudStream desktop `installSource` null-checked `pluginUrl` *after* already
  using `pluginUrl!`.** Reordered.

### Correctness fixes

- **`DownloadablePlugin._download` corrupted files on resume.** It picked
  `FileMode.append` purely from "a `.tmp` exists", so when the server answered a
  `Range` request with a full `200` body (common — GitHub / jsDelivr do this) it
  appended the whole file onto the stale partial. Now only appends on a real
  `206`; a `200` truncates and restarts.
- **`detectUpdates` never cleared a stale `hasUpdate`.** Once flagged, a source
  kept offering an update even after it was applied or the repo rolled back.
  Every `detectUpdates` (Tachiyomi-shared, Mangayomi, Sora, CloudStream x2,
  IReader-desktop) now clears the flag when the repo is no longer ahead.
- **`detectTachiyomiUpdates` only carried `apkName` on an update**, not
  `apkUrlOverride` / `jarUrl` / `pkgName` — so on desktop a detected `.pb`
  update would re-download the *installed* version (the URL encodes the
  version). Now carries all download-relevant fields.
- **CloudStream `detectUpdates` rebuilt the installed Rx list on every call**
  even with nothing changed. Added a `changed` guard.
- **CloudStream desktop `initializeDesktop` uses `bridge/aniyomi`** while every
  other path in the class is `bridge/cloudStream`. Left as-is with a comment —
  the desktop sidecar contract is in `runtimeManager`, out of scope here.

### Tests

- `test/services/download_package_file_test.dart` — new, 3 cases (200 writes &
  cleans up `.tmp`, non-200 throws & leaves no file, replaces an existing file).
- `test/services/tachiyomi_repo_test.dart` — +2 cases for the derived `apkUrl`.
- `dart analyze lib test` clean · `flutter test` 44 pass.
