package com.aayush262.dartotsu_extension_bridge


import android.annotation.SuppressLint
import android.app.Application
import androidx.core.net.toUri
import androidx.preference.*
import com.aayush262.dartotsu_extension_bridge.aniyomi.*
import eu.kanade.tachiyomi.PreferenceScreen
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.online.HttpSource
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get

class AniyomiExtensionApi(
) : ExtensionApi {

    private val sourcePreferences =
        mutableMapOf<String, MutableMap<String, PrefHandlers>>()

    private fun media(sourceId: String, isAnime: Boolean) =
        if (isAnime) AnimeSourceMethods(sourceId)
        else MangaSourceMethods(sourceId)

    override suspend fun getInstalledAnimeExtensions(path: String?): List<Map<String, Any?>> {
        return Injekt.get<AniyomiExtensionManager>()
            .fetchInstalledAnimeExtensions(path)
            .flatMap { ext ->
                ext.sources.map { source ->

                    val baseUrl = (source as? AnimeHttpSource)?.baseUrl.orEmpty()

                    mapOf(
                        "id" to source.id.toString(),
                        "name" to ext.name,
                        "baseUrl" to baseUrl,
                        "lang" to source.lang,
                        "isNsfw" to ext.isNsfw,
                        "iconUrl" to ext.iconUrl,
                        "version" to ext.versionName,
                        "pkgName" to ext.pkgName,
                        "itemType" to 1,
                        "hasUpdate" to ext.hasUpdate,
                        "isObsolete" to ext.isObsolete,
                        "isShared" to ext.isShared,
                    )
                }
            }
    }

    override suspend fun getInstalledMangaExtensions(): List<Map<String, Any?>> {
        return Injekt.get<AniyomiExtensionManager>()
            .fetchInstalledMangaExtensions()
            .flatMap { ext ->
                ext.sources.map { source ->

                    val baseUrl = (source as? HttpSource)?.baseUrl.orEmpty()

                    mapOf(
                        "id" to source.id,
                        "name" to ext.name,
                        "baseUrl" to baseUrl,
                        "lang" to source.lang,
                        "isNsfw" to ext.isNsfw,
                        "iconUrl" to ext.iconUrl,
                        "version" to ext.versionName,
                        "pkgName" to ext.pkgName,
                        "itemType" to 0,
                        "hasUpdate" to ext.hasUpdate,
                        "isObsolete" to ext.isObsolete,
                    )
                }
            }
    }

    // -------------------------
    // Popular / Latest / Search
    // -------------------------

    override suspend fun getPopular(
        sourceId: String,
        isAnime: Boolean,
        page: Int
    ): Map<String, Any?> {

        val res = media(sourceId, isAnime).getPopular(page)

        return mapOf(
            "list" to res.animes.map { it.toMap() },
            "hasNextPage" to res.hasNextPage
        )
    }

    override suspend fun getLatestUpdates(
        sourceId: String,
        isAnime: Boolean,
        page: Int
    ): Map<String, Any?> {

        val res = media(sourceId, isAnime).getLatestUpdates(page)

        return mapOf(
            "list" to res.animes.map { it.toMap() },
            "hasNextPage" to res.hasNextPage
        )
    }

    override suspend fun search(
        sourceId: String,
        isAnime: Boolean,
        query: String,
        page: Int
    ): Map<String, Any?> {

        val res = media(sourceId, isAnime).getSearchResults(query, page)

        return mapOf(
            "list" to res.animes.map { it.toMap() },
            "hasNextPage" to res.hasNextPage
        )
    }

    // -------------------------
    // Details
    // -------------------------

    override suspend fun getDetail(
        sourceId: String,
        isAnime: Boolean,
        media: Map<String, Any?>
    ): Map<String, Any?> {

        val anime = SAnime.create().apply {
            title = media["title"] as String
            url = media["url"] as String
            thumbnail_url = media["thumbnail_url"] as? String
            description = media["description"] as? String
            artist = media["artist"] as? String
            author = media["author"] as? String
            genre = media["genre"] as? String
        }

        val media = media(sourceId, isAnime)

        val details = media.getDetails(anime)

        val episodes =
            if (isAnime) media.getEpisodeList(anime)
            else media.getChapterList(anime)

        return mapOf(
            "title" to anime.title,
            "url" to anime.url,
            "cover" to anime.thumbnail_url,
            "artist" to details.artist,
            "author" to details.author,
            "description" to details.description,
            "genre" to details.getGenres(),
            "status" to details.status,
            "episodes" to episodes.map {
                mapOf(
                    "name" to it.name,
                    "url" to it.url,
                    "date_upload" to it.date_upload,
                    "episode_number" to it.episode_number,
                    "scanlator" to it.scanlator
                )
            }
        )
    }

    // -------------------------
    // Videos
    // -------------------------

    override suspend fun getVideoList(
        sourceId: String,
        isAnime: Boolean,
        episodeMap: Map<String, Any?>
    ): List<Map<String, Any?>> {

        val ep = SEpisode.create().apply {
            name = episodeMap["name"] as String
            url = episodeMap["url"] as String
            episode_number =
                (episodeMap["episode_number"] as? Double)?.toFloat() ?: 0f
            scanlator = episodeMap["scanlator"] as? String
        }

        return media(sourceId, isAnime).getVideoList(ep).map {

            mapOf(
                "title" to it.videoTitle,
                "url" to it.videoUrl,
                "quality" to it.resolution,
                "headers" to it.headers?.toMap(),
                "subtitles" to it.subtitleTracks.map { t ->
                    mapOf("file" to t.url, "label" to t.lang)
                },
                "audios" to it.audioTracks.map { t ->
                    mapOf("file" to t.url, "label" to t.lang)
                }
            )
        }
    }

    // -------------------------
    // Pages
    // -------------------------

    override suspend fun getPageList(
        sourceId: String,
        isAnime: Boolean,
        episodeMap: Map<String, Any?>
    ): List<Map<String, Any?>> {

        val chapter = SChapter.create().apply {
            name = episodeMap["name"] as String
            url = episodeMap["url"] as String
        }

        val media = media(sourceId, isAnime)

        return media.getPageList(chapter)
            .map { it.toPayload(media.baseUrl ?: "") }
    }

    // -------------------------
    // Preferences
    // -------------------------

    @SuppressLint("RestrictedApi")
    override suspend fun getPreference(
        sourceId: String,
        isAnime: Boolean
    ): List<Map<String, Any?>> {

        sourcePreferences.remove(sourceId)
        val context: Application = Injekt.get()
        val screen = PreferenceManager(context)
            .createPreferenceScreen(context)

        media(sourceId, isAnime)
            .setupPreferenceScreen(screen)

        return screen.toDynamicMap(sourceId)
    }

    override suspend fun saveSourcePreference(
        sourceId: String,
        key: String,
        action: String,
        value: Any?
    ): Boolean {

        val handler = sourcePreferences[sourceId]?.get(key) ?: return false
        val pref = handler.pref

        if (action == "click") handler.click?.onPreferenceClick(pref)
        else handler.change?.onPreferenceChange(pref, value)

        when (pref) {

            is SwitchPreferenceCompat ->
                pref.isChecked = value as Boolean

            is ListPreference ->
                pref.value = value as String

            is EditTextPreference ->
                pref.text = value as String

            is MultiSelectListPreference -> {
                val newSet = when (value) {
                    is List<*> -> value.filterIsInstance<String>().toSet()
                    is Set<*> -> value.filterIsInstance<String>()
                    else -> emptySet()
                }
                pref.values = newSet.toMutableSet()
            }

            is CheckBoxPreference ->
                pref.isChecked = value as Boolean
        }

        return true
    }

    // -------------------------
    // Helpers
    // -------------------------


    private fun Page.toPayload(baseUrl: String): Map<String, Any> {

        val uri = imageUrl!!.toUri()

        val headers = uri.queryParameterNames.associateWith {
            uri.getQueryParameter(it).orEmpty()
        } + mapOf(
            "Referer" to "$baseUrl/",
            "Origin" to baseUrl
        )

        return mapOf(
            "url" to imageUrl!!,
            "headers" to headers
        )
    }

    private fun PreferenceScreen.toDynamicMap(sourceId: String): List<Map<String, Any?>> {

        val list = mutableListOf<Map<String, Any?>>()

        val store = sourcePreferences
            .getOrPut(sourceId) { mutableMapOf() }

        fun walk(group: PreferenceGroup) {

            for (i in 0 until group.preferenceCount) {

                val p = group.getPreference(i)

                store[p.key] =
                    PrefHandlers(p, p.onPreferenceClickListener, p.onPreferenceChangeListener)

                val map = mutableMapOf<String, Any?>(
                    "key" to p.key,
                    "title" to p.title?.toString(),
                    "summary" to p.summary?.toString(),
                    "enabled" to p.isEnabled,
                    "type" to when (p) {
                        is ListPreference -> "list"
                        is MultiSelectListPreference -> "multi_select"
                        is SwitchPreferenceCompat -> "switch"
                        is EditTextPreference -> "text"
                        is CheckBoxPreference -> "checkbox"
                        else -> "other"
                    },
                    "value" to when (p) {
                        is ListPreference -> p.value
                        is MultiSelectListPreference -> p.values.toList()
                        is SwitchPreferenceCompat -> p.isChecked
                        is EditTextPreference -> p.text
                        is CheckBoxPreference -> p.isChecked
                        else -> null
                    }
                )

                list += map

                if (p is PreferenceCategory) walk(p)
            }
        }

        walk(this)

        return list
    }

    private data class PrefHandlers(
        val pref: Preference,
        val click: Preference.OnPreferenceClickListener?,
        val change: Preference.OnPreferenceChangeListener?
    )
}


private fun SAnime.toMap() = mapOf(
    "title" to title,
    "url" to url,
    "cover" to thumbnail_url,
    "artist" to artist,
    "author" to author,
    "description" to description,
    "genre" to getGenres(),
    "status" to status,
)