# Aniyomi / Tachiyomi runtime — update status

Scope: `runtimeManager/aniyomi/**` and the Dart repo layer.

## Done

### Source API synced to upstream

The vendored `eu.kanade.tachiyomi` tree is now level with the **stub repos that
extensions actually compile against** — not the app monorepos:

| | upstream | was | now |
|---|---|---|---|
| anime | [`aniyomiorg/extensions-lib`](https://github.com/aniyomiorg/extensions-lib) | extensions-lib 16 | **17** |
| manga | [`mihonapp/tachiyomix`](https://github.com/mihonapp/tachiyomix) | tachiyomix 1.6 | **1.7** |

**extensions-lib 17**
- `SAnime`: `memo: JsonObject`, status `UPCOMING = 7`
- `SEpisode`: `memo: JsonObject`
- `Hoster`: `memo: JsonObject`
- new: `AnimeRelation`, `ThumbnailInfo` + `TileInfo`, `SAnimeEpisodeUpdate`, `SAnimeSeasonUpdate`
- `AnimeSource`: `getAnimeEpisodeUpdate`, `getAnimeSeasonUpdate`,
  `supportsRelatedAnime`, `getRelatedAnimeList`

**tachiyomix 1.7**
- `SManga`: `altTitles`, `banner`, `language`, `contentRating`, `score`,
  `readingMode`, and `genre: String?` → `genres: List<String>`
- `SChapter`: `volume`, `number`, `scanlators`, `language`, `locked`, `note`,
  and `chapter_number: Float` → `number: String?`, `scanlator` → `scanlators`
- `Source`: `language`

### Backwards compatibility

Extensions published against the *old* API keep working. Every renamed member is
retained as a deprecated bridge property with a default get/set that delegates to
the new field, so old bytecode (`getGenre`, `setChapter_number`, `getScanlator`,
`lang`) still resolves:

| old | bridges to |
|---|---|
| `SManga.genre: String?` | `genres` joined with `", "` |
| `SChapter.chapter_number: Float` | `number` parsed as float, `-1f` when absent |
| `SChapter.scanlator: String?` | `scanlators` joined with `", "` |
| `Source.language` | defaults to `lang` |

The new `AnimeSource` methods all have default bodies that fan out to
`getAnimeDetails` / `getEpisodeList` / `getSeasonList`, and `getSeasonList` is no
longer abstract — so a lib-16 extension satisfies the lib-17 interface unchanged.

`Hoster.internalData` was **not** raised to upstream's `DeprecationLevel.ERROR`,
because extensions still set it.

### index.pb repositories

Mihon/keiyoushi's gzipped-protobuf `index.pb` is supported alongside
`index.min.json`. Paste e.g.
`https://github.com/keiyoushi/extensions/raw/repo/index.pb` as a repo URL.

- `lib/Services/Shared/ProtoReader.dart` — small protobuf wire reader; no
  `package:protobuf` dependency or codegen
- `lib/Services/Shared/TachiyomiRepo.dart` — `RepoIndexFormat`,
  `parseTachiyomiPbIndex`, `tachiyomiPbExtensionListUrl`,
  `fetchTachiyomiRepoIndex`
- Field numbers mirror mihon's `NetworkExtensionStore`; `isNsfw` is
  `contentWarning >= MIXED` and `lang` collapses to `"all"` for multi-language
  extensions, both matching Mihon
- `.pb` states the APK URL outright (keiyoushi also ships a desktop jar at field
  501), so `PackagedSource` gained `apkUrlOverride` / `jarUrl`

## Verification

- `./gradlew buildAllPlugins` → BUILD SUCCESSFUL (all 8 artifacts)
- `dart analyze lib test` clean; 37 plugin tests, 12 app tests
- `flutter build linux --debug` on Dartotsu-rewrite-re → OK
- `index.pb` decoder checked against the live keiyoushi index: 1383 manga
  extensions, correct 64-bit source ids / versions / nsfw flags
- Fresh jar installed at
  `~/Documents/Dartotsu/bridge/plugins/aniyomiDesktop-plugin.jar`
  (previous one kept as `*.bak-20260910`)

## Still open

- **`HttpServer` (extensions-lib 17) is not implemented.** It extends
  `NanoHTTPD`, which the fork doesn't depend on. Extensions that subclass it will
  fail to load; nothing else is affected. Adding it means pulling in
  `org.nanohttpd:nanohttpd` and wiring `Video.usesHttpServer()` /
  `copyHttpServer()`.
- `Video.memo` (lib 17) not added — `Video` is a `@Serializable` data class in
  this fork with its own compat constructors, so it needs a more careful pass.
- Runtime behaviour is unverified: everything here is compile- and unit-verified
  only. Loading a real extension and calling `getPopular` / `search` /
  `getVideoList` still needs a manual pass in the app.
- Building `:aniyomi:aniyomiAndroid` **in isolation** fails with
  `Unresolved reference 'CustomMethods'` — `aniyomiCommon/build.gradle.kts` only
  puts `commonDesktopLib` on `commonMain`'s classpath when no invoked task name
  contains "Android", yet `commonMain` references the desktop-only
  `CustomMethods`. Works via `buildAllPlugins`. Worth fixing separately.

## 2026-09-10 — "new extensions stopped loading" was a concurrency bug, not BytecodeEditor

Symptom: v1.6.x keiyoushi extensions failed with
`ClassNotFoundException: keiyoushi.source.Generated` from
`URLClassLoader.findClass`, i.e. the class was missing from the freshly built
jar even though `BytecodeEditor` logged it as processed fine.

Not a bytecode-repair regression. Verified: the deployed
`aniyomiDesktop-plugin.jar` loads **129/129** manga sources (all the v1.6
keiyoushi ones included) when a single `getInstalledMangaExtensions` runs. The
`Generated` class parses, its `Filter.Group` / `Filter.TriState` construction
sites repair via the DEX oracle, and it verifies.

Root cause: the desktop loaders run **concurrently** — the sidecar `Server.run`
fans every request onto `requestScope`, and the app polls
`getInstalledMangaExtensions`. Two loads of the same APK at once both wrote the
*same* jar path in place:

- `PackageTools.dex2jar` ran `Dex2jar.to(finalJarPath)` then
  `BytecodeEditor.fixAndroidClasses(finalJarPath)` — an in-place
  `FileSystems.newFileSystem` mutation.
- `PackageTools.extractAssetsFromApk` did `jarFile.delete()` +
  `tempJar.renameTo(jarFile)` with a fixed `*_temp.jar` name and a shared
  `*_assets/` dir.
- `PackageTools.jarLoaderMap` was a plain `mutableMap`.

A racing `URLClassLoader` then opened a half-written jar → some entries
unreadable → `ClassNotFoundException`. Repro: 3× concurrent
`getInstalledMangaExtensions` on a cold jar dir returned **46 / 64 / 64**
sources instead of 129.

Fix (`PackageTools.kt` + `BytecodeEditor.kt`, atomic-write pattern borrowed
from M-Extension-Server's `fixAndroidClasses`):

- `dex2jar`: convert into a private `Files.createTempFile`, run
  `BytecodeEditor` on that, then one `Files.move(REPLACE_EXISTING)` into place.
- `BytecodeEditor.fixAndroidClasses`: `readJarEntries` into memory → rewrite →
  `ZipOutputStream` to a temp jar → `Files.move`. Drops duplicate central-dir
  entries on the way. No more `FileSystems.newFileSystem` / `FileSystemAlready
  ExistsException`.
- `extractAssetsFromApk`: unique `Files.createTempDirectory` /
  `Files.createTempFile`, atomic `Files.move` instead of `delete` + `renameTo`.
- `jarLoaderMap` → `ConcurrentHashMap` + `computeIfAbsent`.

After: 3× concurrent `getInstalledMangaExtensions` on a cold jar dir → **128 /
128 / 128**, zero `ClassNotFoundException` (sequential still 129; the 128/129
gap under load is a separate, non-fatal dedup/timing nit, not corruption).
