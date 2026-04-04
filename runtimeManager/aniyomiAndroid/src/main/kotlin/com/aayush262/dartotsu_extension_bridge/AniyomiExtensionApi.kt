package com.aayush262.dartotsu_extension_bridge

import android.annotation.SuppressLint
import android.app.Application
import android.content.Context
import androidx.core.net.toUri
import androidx.preference.*
import com.google.gson.Gson
import com.aayush262.dartotsu_extension_bridge.aniyomi.*
import com.aayush262.dartotsu_extension_bridge.network.Network.enableNetworking
import eu.kanade.tachiyomi.PreferenceScreen
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.online.HttpSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingletonFactory
import uy.kohesive.injekt.api.get
import androidx.core.content.edit

var customAniyomiMethods: CustomMethods? = null

class AniyomiExtensionApi : ExtensionApi, AniyomiCustomMethods {

    private val sourcePreferences = mutableMapOf<String, MutableMap<String, Preference>>()

    private fun media(sourceId: String, isAnime: Boolean) = if (isAnime) AnimeSourceMethods(sourceId)
    else MangaSourceMethods(sourceId)

    override fun initialize(customMethods: CustomMethods) {
        customAniyomiMethods = customMethods
    }

    override fun initClient(data: Map<*, *>) {
        enableNetworking(data)
    }

    override fun initializeAndroid(context: Any) {
        val ctx = context as? Context ?: return
        Injekt.addSingletonFactory<Application> { ctx as Application }

        Injekt.addSingletonFactory { NetworkHelper(ctx) }
        Injekt.addSingletonFactory { Injekt.get<NetworkHelper>().client }

        Injekt.addSingletonFactory {
            Json {
                ignoreUnknownKeys = true
                explicitNulls = false

            }
        }

        Injekt.addSingletonFactory { AniyomiExtensionManager(ctx) }

    }
    private val gson = Gson()

    private fun encode(data: Any?): String =
        gson.toJson(data)

    @Suppress("UNCHECKED_CAST")
    private fun decode(json: String): Map<String, Any?> =
        gson.fromJson(json, Map::class.java) as Map<String, Any?>

    override suspend fun getInstalledAnimeExtensions(path: String?): String {
        path ?: return "[]"

        val result = withContext(Dispatchers.IO) {
            Injekt.get<AniyomiExtensionManager>()
                .fetchInstalledAnimeExtensions(path)
                .flatMap { ext ->
                    ext.sources.map { source ->
                        mapOf(
                            "id" to source.id,
                            "name" to source.name,
                            "baseUrl" to (source as? AnimeHttpSource)?.baseUrl.orEmpty(),
                            "lang" to source.lang,
                            "isNsfw" to ext.isNsfw,
                            "iconUrl" to ext.iconUrl,
                            "version" to ext.versionName,
                            "pkgName" to ext.pkgName,
                            "itemType" to 1
                        )
                    }
                }
        }

        val nameCounts = result.groupingBy { it["name"] }.eachCount()

        return encode(
            result.map { item ->
                val name = item["name"] as String
                val lang = item["lang"] as String

                if (nameCounts[name]!! > 1) {
                    item + ("name" to "$name ($lang)")
                } else {
                    item
                }
            },
        )
    }

    override suspend fun getInstalledMangaExtensions(path: String?): String {
        path ?: return "[]"

        val result = withContext(Dispatchers.IO) {
            Injekt.get<AniyomiExtensionManager>()
                .fetchInstalledMangaExtensions(path)
                .flatMap { ext ->
                    ext.sources.map { source ->
                        mapOf(
                            "id" to source.id,
                            "name" to source.name,
                            "baseUrl" to (source as? HttpSource)?.baseUrl.orEmpty(),
                            "lang" to source.lang,
                            "isNsfw" to ext.isNsfw,
                            "iconUrl" to ext.iconUrl,
                            "version" to ext.versionName,
                            "pkgName" to ext.pkgName,
                            "itemType" to 0
                        )
                    }
                }
        }

        val nameCounts = result.groupingBy { it["name"] }.eachCount()

        return encode(
            result.map { item ->
                val name = item["name"] as String
                val lang = item["lang"] as String

                if (nameCounts[name]!! > 1) {
                    item + ("name" to "$name ($lang)")
                } else {
                    item
                }
            },
        )
    }

    override suspend fun getPopular(sourceId: String, isAnime: Boolean, page: Int): String {
        val res = withContext(Dispatchers.IO) {
            media(sourceId, isAnime).getPopular(page)
        }

        return encode(
            mapOf(
                "list" to res.animes.map { it.toMap() },
                "hasNextPage" to res.hasNextPage
            )
        )
    }

    override suspend fun getLatestUpdates(sourceId: String, isAnime: Boolean, page: Int): String {
        val res = withContext(Dispatchers.IO) {
            media(sourceId, isAnime).getLatestUpdates(page)
        }

        return encode(
            mapOf(
                "list" to res.animes.map { it.toMap() },
                "hasNextPage" to res.hasNextPage
            )
        )
    }

    override suspend fun search(sourceId: String, isAnime: Boolean, query: String, page: Int): String {
        val res = withContext(Dispatchers.IO) {
            media(sourceId, isAnime).getSearchResults(query, page)
        }

        return encode(
            mapOf(
                "list" to res.animes.map { it.toMap() },
                "hasNextPage" to res.hasNextPage
            )
        )
    }


    override suspend fun getDetail(
        sourceId: String,
        isAnime: Boolean,
        media: String
    ): String = withContext(Dispatchers.IO) {

        val mediaMap: Map<String, Any?> = decode(media)

        val anime = SAnime.create().apply {
            title = mediaMap["title"] as String
            url = mediaMap["url"] as String
            thumbnail_url = mediaMap["thumbnail_url"] as? String
            description = mediaMap["description"] as? String
            artist = mediaMap["artist"] as? String
            author = mediaMap["author"] as? String
            genre = mediaMap["genre"] as? String
        }

        val mediaSource = media(sourceId, isAnime)

        val details = mediaSource.getDetails(anime)

        val episodes = if (isAnime)
            mediaSource.getEpisodeList(anime)
        else
            mediaSource.getChapterList(anime)

        val result = mapOf(
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

        return@withContext encode(result)
    }


    override suspend fun getVideoList(
        sourceId: String,
        isAnime: Boolean,
        episode: String
    ): String = withContext(Dispatchers.IO) {

        val epMap = decode(episode)

        val ep = SEpisode.create().apply {
            name = epMap["name"] as String
            url = epMap["url"] as String
            episode_number = (epMap["episode_number"] as? Double)?.toFloat() ?: 0f
            scanlator = epMap["scanlator"] as? String
        }

        val result = media(sourceId, isAnime).getVideoList(ep).map {
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
                },
                "timestamps" to it.timestamps.map { t ->
                    mapOf(
                        "name" to t.name,
                        "startTime" to t.start,
                        "endTime" to t.end
                    )
                }
            )
        }

        return@withContext encode(result)
    }

    override suspend fun getPageList(sourceId: String, isAnime: Boolean, episode: String): String {
        val epMap: Map<String, Any?> = decode(episode)

        val chapter = SChapter.create().apply {
            name = epMap["name"] as String
            url = epMap["url"] as String
        }

        val pages = withContext(Dispatchers.IO) {
            media(sourceId, isAnime).getPageList(chapter)
        }

        val source = media(sourceId, isAnime)

        return encode(
            pages.map { it.toPayload(source.baseUrl ?: "") }
        )
    }

    private fun Page.toPayload(baseUrl: String): Map<String, Any> {

        val uri = imageUrl!!.toUri()

        val headers = uri.queryParameterNames.associateWith {
            uri.getQueryParameter(it).orEmpty()
        } + mapOf(
            "Referer" to "$baseUrl/", "Origin" to baseUrl
        )

        return mapOf(
            "url" to imageUrl!!, "headers" to headers
        )
    }

    @SuppressLint("RestrictedApi")
    override suspend fun getPreference(
        sourceId: String, isAnime: Boolean
    ): String {

        sourcePreferences.remove(sourceId)

        val context: Application = Injekt.get()

        val prefManager = PreferenceManager(context)

        prefManager.sharedPreferencesName = "source_$sourceId"
        prefManager.sharedPreferencesMode = Context.MODE_PRIVATE

        val screen = prefManager.createPreferenceScreen(context)

        media(sourceId, isAnime).setupPreferenceScreen(screen)

        return encode(screen.toDynamicMap(sourceId))
    }

    override suspend fun saveSourcePreference(sourceId: String, key: String, value: String?): Boolean {

        val pref = sourcePreferences[sourceId]?.get(key) ?: return false

        if (value == null) {
            return false
        }

        val payload = try {
            decode(value)
        } catch (_: Exception) {
            return false
        }

        val raw = payload["value"]
        withContext(Dispatchers.Main) {

            val prefs = pref.sharedPreferences ?: return@withContext

            val convertedValue = when (raw) {
                is List<*> -> raw.filterIsInstance<String>().toMutableSet()
                is Set<*> -> raw.filterIsInstance<String>().toMutableSet()
                else -> raw
            }

            prefs.edit(commit = true) {

                when (convertedValue) {

                    is Boolean -> putBoolean(key, convertedValue)

                    is String -> putString(key, convertedValue)

                    is Int -> putInt(key, convertedValue)

                    is Long -> putLong(key, convertedValue)

                    is Float -> putFloat(key, convertedValue)

                    is Set<*> -> putStringSet(
                        key, convertedValue.filterIsInstance<String>().toMutableSet()
                    )

                    null -> remove(key)

                    else -> error("Unsupported preference type: ${convertedValue::class}")
                }
            }

            pref.onPreferenceChangeListener?.onPreferenceChange(pref, convertedValue)
        }

        return true
    }


    fun PreferenceScreen.toDynamicMap(sourceID: String): List<Map<String, Any?>> {
        val list = mutableListOf<Map<String, Any?>>()
        val clickMap = sourcePreferences.getOrPut(sourceID) { mutableMapOf() }
        fun traverse(prefGroup: PreferenceGroup) {
            for (i in 0 until prefGroup.preferenceCount) {
                val pref = prefGroup.getPreference(i)

                clickMap[pref.key] = pref
                val prefMap = mutableMapOf<String, Any?>(
                    "key" to pref.key, "title" to pref.title.toString(), "summary" to pref.summary?.toString(), "enabled" to pref.isEnabled, "type" to when (pref) {
                        is ListPreference -> "list"
                        is MultiSelectListPreference -> "multi_select"
                        is SwitchPreferenceCompat -> "switch"
                        is EditTextPreference -> "text"
                        is CheckBoxPreference -> "checkbox"
                        else -> "other"
                    }
                )
                when (pref) {
                    is ListPreference -> {
                        prefMap["entries"] = pref.entries.map { it.toString() }
                        prefMap["entryValues"] = pref.entryValues.map { it.toString() }
                        prefMap["value"] = pref.value
                    }

                    is MultiSelectListPreference -> {
                        prefMap["entries"] = pref.entries.map { it.toString() }
                        prefMap["entryValues"] = pref.entryValues.map { it.toString() }
                        prefMap["value"] = pref.values.toList()
                    }

                    is SwitchPreferenceCompat -> {
                        prefMap["value"] = pref.isChecked
                    }

                    is EditTextPreference -> {
                        prefMap["value"] = pref.text
                    }

                    is CheckBoxPreference -> {
                        prefMap["value"] = pref.isChecked
                    }

                    else -> {
                        prefMap["value"] = pref.sharedPreferences?.all?.get(pref.key)
                    }
                }
                list.add(prefMap)

                if (pref is PreferenceCategory) {
                    traverse(pref)
                }
            }
        }

        traverse(this)
        return list
    }


}

private fun SAnime.toMap() = mapOf(
    "title" to title, "url" to url, "cover" to thumbnail_url, "artist" to artist, "author" to author, "description" to description, "genre" to getGenres(), "status" to status
)