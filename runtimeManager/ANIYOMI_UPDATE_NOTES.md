# Aniyomi / Tachiyomi runtime — update status & plan

Session date: 2026-09-10. Scope: `runtimeManager/aniyomi/**`.

## TL;DR

- **Done now (safe, build-verified):** dependency version bumps for the Aniyomi
  build (okhttp 5.4→5.5, jsoup 1.22→1.23, gson 2.13→2.14, okio 3.17→3.18,
  androidx-core 1.16→1.19, commons-text 1.11→1.15). Fresh
  `aniyomiDesktop-plugin.jar` produced and copied to
  `~/Documents/Dartotsu/bridge/plugins/` for in-app testing.
- **Not done (needs a human pass):** syncing the vendored `eu.kanade.tachiyomi.*`
  source-api to upstream **extensions-lib 17**. This is a real API-version jump,
  not a copy-paste, because the fork carries deliberate divergences (below).

## How the Aniyomi runtime is structured

`runtimeManager/aniyomi/aniyomiCommon/src/{commonMain,androidMain,desktopMain}` is
a **KMP fork** of:
- Aniyomi `source-api` (`eu.kanade.tachiyomi.animesource.*`, `.source.*`)
- Aniyomi/Mihon `core` networking (`eu.kanade.tachiyomi.network.*`) — NOT in
  upstream `source-api`, pulled from the app module
- Aniyomi torrent server bits (`torrentServer/`, `torrentutils/`)
- glue under `com/aayush262/dartotsu_extension_bridge/**`

It is **not** a git submodule and has no recorded upstream base commit.

## Delta vs upstream `aniyomiorg/aniyomi@main` `source-api` (fetched 2026-09-10)

`same` (already current): `AnimeSourceFactory`, `AnimeFilter`, `AnimeUpdateStrategy`,
`FetchType`, `ResolvableAnimeSource`, `animesource/UnmeteredSource`,
`source/model/Page`, `source/model/UpdateStrategy`, `source/UnmeteredSource`,
`util/JsonExtensions`, `util/JsoupExtensions`.

`NEW upstream files to add` (all small, mostly additive):
| file | notes |
|---|---|
| `animesource/model/SAnimeEpisodeUpdate.kt` | `class SAnimeEpisodeUpdate(val anime, val episodes)` |
| `animesource/model/SAnimeSeasonUpdate.kt`  | `class SAnimeSeasonUpdate(val anime, val seasons)` |
| `animesource/model/AnimeRelation.kt`       | `class AnimeRelation(name, animes)` — related-anime feature |
| `animesource/model/ThumbnailInfo.kt`       | `ThumbnailInfo` + `data class TileInfo` — scrubber previews |
| `animesource/model/HttpServer.kt`          | **pulls `fi.iki.elonen:nanohttpd` + `logcat` + `tachiyomi.core.common...logcat`** — needs infra or a stub |
| `source/MangaSource.kt`                    | manga counterpart of the reworked `AnimeSource` (still Rx-compat) |
| `util/VideoInfo.kt`                        | `sealed class Video; data class VideoUrl` (unrelated to `animesource.model.Video`) |
| `androidMain/.../animesource/PreferenceScreen.kt`, `source/PreferenceScreen.kt`, `util/RxExtension.kt` | `actual` decls — only if we adopt the upstream `expect/actual awaitSingle` |

`CHANGED` (diff lines), biggest first — each needs a 3-way merge, not overwrite:
| file | Δ | why not a straight copy |
|---|---|---|
| `animesource/online/AnimeHttpSource.kt` | 322 | base class every anime ext extends; extensions-lib 17 method set |
| `source/online/HttpSource.kt` | 317 | base class every manga ext extends |
| `torrentutils/TorrentUtils.kt` | 252 | Aniyomi-app code, fork may have local edits |
| `animesource/AnimeSource.kt` | 158 | **interface redesign**: `getPopularAnime`/`getLatestUpdates`/`getSearchAnime` move here from `AnimeCatalogueSource`; new `getAnimeEpisodeUpdate(anime,episodes,fetchDetails,fetchEpisodes)` + `getAnimeSeasonUpdate(...)` **replace** `getAnimeDetails`/`getEpisodeList`/`getSeasonList` (now deprecated stubs); new `getRelatedAnimeList` + `supportsRelatedAnime` |
| `source/CatalogueSource.kt` | 123 | mirror of the above on the manga side |
| `animesource/model/Video.kt` | 95 | adds `memo: JsonObject = JsonObject.EMPTY` (**needs `mihon.core.common.extensions.EMPTY`**), `usesHttpServer()`, `copyHttpServer(port)`, ext-lib-16 compat ctor/copy |
| `animesource/AnimeCatalogueSource.kt` | 84 | now `override`s the new suspend API with default impls that fan out to the deprecated Rx methods (this is the back-compat shim that keeps old APKs working) |
| `source/model/Filter.kt` | 65 | ⚠️ upstream is `sealed class`; **fork deliberately made it `open class`** ("Tachidesk adds subclasses for serialization"). Keep the fork's version. |
| `animesource/online/ParsedAnimeHttpSource.kt` / `source/online/ParsedHttpSource.kt` | 31 / 28 | follow the base-class changes |
| `animesource/model/Hoster.kt` | 29 | new fields |
| `animesource/model/SAnime.kt` | 28 | field reorder + `var memo: JsonObject` (`@since extensions-lib 17`) + `UPCOMING = 7` status |
| `animesource/utils/Preferences.kt` | 38 | |
| `source/model/SManga.kt` / `SChapter.kt` | 25 / 21 | ⚠️ fork **already has `memo`** (from tachiyomix 1.6); upstream Aniyomi `source/` does *not*. Fork is ahead here — do not regress. |
| `source/model/MangasPage.kt`, `animesource/model/AnimesPage.kt`, `*Impl.kt`, `FilterList.kt`, `SourceFactory.kt`, `ConfigurableSource.kt`, `ResolvableSource.kt`, `ConfigurableAnimeSource.kt` | 1–18 | mostly formatting / import order / tiny field adds |

## Fork divergences that MUST be preserved through any sync

1. `source/model/Filter.kt` is `open class`, not `sealed` (serialization).
2. No `mihon.core.common.*` / `tachiyomi.core.common.*` dependency. The fork
   supplies its own `eu.kanade.tachiyomi.util.awaitSingle` in
   `util/RxCoroutineBridge.kt` (direct fun, no `expect/actual`). Upstream files
   `import tachiyomi.core.common.util.lang.awaitSingle` and use
   `JsonObject.EMPTY` / `logcat` from Mihon core — rewrite those imports or add
   local shims (`JsonObject.EMPTY` = `JsonObject(emptyMap())`).
3. KMP `expect/actual` for platform bits (`network/interceptor/CloudflareInterceptor`,
   `util/system/ChildFirst*ClassLoader` — desktop classloading).
4. Non-upstream trees kept as-is: `network/**`, `util/system/**`,
   `util/lang/CoroutinesExtensions.kt`, `torrentServer/**`, `AppInfo.kt`,
   top-level `PreferenceScreen.kt`, `source/model/RefreshContext.kt`,
   `source/model/SMangaUpdate.kt`.

## Glue call-sites to update after an API bump

`aniyomiCommon/src/commonMain/.../com/aayush262/dartotsu_extension_bridge/`:
- `aniyomi/AnimeSourceMethods.kt` — calls `source.getAnimeDetails(media)`,
  `source.getEpisodeList(media)`, `source.getSeasonList(media)`,
  `source.getVideoList(episode)`, `source.getHosterList(episode)`,
  `source.getVideoList(hoster)`. With ext-lib 17 the first three become
  deprecated on `AnimeSource` but remain working on `AnimeHttpSource`, so this
  likely still compiles; verify against the reworked `AnimeCatalogueSource`
  shim. Prefer migrating to `getAnimeEpisodeUpdate` / `getAnimeSeasonUpdate`.
- `AniyomiExtensionApi.kt` — `getVideoList(...)` path.
- `aniyomi/MangaSourceMethods.kt`, `aniyomi/AniyomiSourceMethods.kt`.

## Suggested execution order for the real sync

1. Add the `same`-if-copied new model files (`SAnime*Update`, `AnimeRelation`,
   `ThumbnailInfo`, `VideoInfo`), `SAnime.memo` + `UPCOMING`.
2. Port `AnimeSource` + `AnimeCatalogueSource` + `AnimeHttpSource` together
   (they only make sense as a set); keep the deprecated Rx methods as working
   overrides so installed APKs keep loading.
3. `Video.kt`: add `memo` with a local `JsonObject.EMPTY` shim; port
   `usesHttpServer()` / `copyHttpServer()` only if wiring `HttpServer`.
4. Rebuild `:aniyomi:aniyomiCommon:compileDesktopMainKotlin`, fix, then
   `:aniyomi:aniyomiDesktop:shadowJar` and `:aniyomi:aniyomiAndroid:assembleRelease`.
5. Drop `aniyomi/aniyomiDesktop/build/libs/aniyomiDesktop-all.jar` →
   `~/Documents/Dartotsu/bridge/plugins/aniyomiDesktop-plugin.jar` and test in app.
6. Manga side (`MangaSource`, `HttpSource`, `CatalogueSource`) is a separate,
   smaller follow-up — the fork already tracks tachiyomix 1.6 there.
