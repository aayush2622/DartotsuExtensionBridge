package com.aayush262.dartotsu_extension_bridge

import android.annotation.SuppressLint
import android.app.Application
import android.os.Looper
import androidx.core.net.toUri
import androidx.preference.CheckBoxPreference
import androidx.preference.EditTextPreference
import androidx.preference.ListPreference
import androidx.preference.MultiSelectListPreference
import androidx.preference.SwitchPreferenceCompat
import com.aayush262.dartotsu_extension_bridge.aniyomi.*
import com.aayush262.dartotsu_extension_bridge.network.Network.enableNetworking
import com.google.gson.Gson
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
import org.koin.core.context.GlobalContext
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import org.koin.core.context.startKoin
import org.koin.dsl.module
import org.koin.mp.KoinPlatformTools
import uy.kohesive.injekt.injectLazy
import xyz.nulldev.androidcompat.androidimpl.CustomContext
import xyz.nulldev.androidcompat.xyz.nulldev.androidcompat.androidCompatModule
import java.io.File
import kotlin.collections.plus
import kotlin.getValue

var customAniyomiMethods: CustomMethods? = null

object DartotsuEnv {
    lateinit var rootDir: String
}

class AniyomiExtensionApi : ExtensionApi, AniyomiCustomMethods {

    override fun initialize(customMethods: CustomMethods) {
        customAniyomiMethods = customMethods
    }

    override fun initClient(data: Map<*, *>) {
        enableNetworking(data)
    }

    @Suppress("DEPRECATION")
    override fun initializeDesktop(basePath: String){
        val root = File(basePath, "aniyomi").apply { mkdirs() }
        DartotsuEnv.rootDir = root.absolutePath

        if (GlobalContext.getOrNull() != null) {
            println("Koin already started")
            return
        }
        val context = object : Application() {}
        val mainLoop = object : Thread() {
            override fun run() {
                Looper.prepareMainLooper()
                Looper.loop()
            }
        }
        mainLoop.start()
        startKoin {
            modules(
                listOf(
                    module {
                        single<Application> { context }
                        single { NetworkHelper(context) }
                        single { Json { ignoreUnknownKeys = true } }
                        single { AniyomiExtensionManager(context) }
                    },
                    androidCompatModule(root),
                )
            )
        }
        val app: CustomContext by KoinPlatformTools.defaultContext().get().inject()
        context.attach(app)
        context.onCreate()
    }

    private fun media(sourceId: String, isAnime: Boolean) =
        if (isAnime) AnimeSourceMethods(sourceId)
        else MangaSourceMethods(sourceId)

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

    val preferenceScreenMap = mutableMapOf<String, PreferenceScreen>()
    private val context: CustomContext by injectLazy()

    @SuppressLint("RestrictedApi")
    override suspend fun getPreference(
        sourceId: String,
        isAnime: Boolean
    ): String {

        val source = media(sourceId, isAnime)

        val prefs = source.getSourcePreferences()

        val screen = PreferenceScreen(context)
        screen.sharedPreferences = prefs

        source.setupPreferenceScreen(screen)

        preferenceScreenMap[sourceId] = screen

        val result = screen.preferences.mapIndexed { index, pref ->

            val key = pref.key

            val value = try {
                pref.currentValue
            } catch (_: Exception) {
                null
            }

            val type = when (pref) {
                is ListPreference -> "list"
                is MultiSelectListPreference -> "multi_select"
                is SwitchPreferenceCompat -> "switch"
                is EditTextPreference -> "text"
                is CheckBoxPreference -> "checkbox"
                else -> "other"
            }
            val summary = pref.summary?.toString()
            val formattedSummary = if (summary?.contains("%s") == true) {

                val entry = when (pref) {
                    is ListPreference -> {
                        val current = pref.currentValue?.toString()

                        val index = pref.entryValues
                            ?.map { it.toString() }
                            ?.indexOf(current)

                        if (index != null && index >= 0) {
                            pref.entries?.get(index)?.toString()
                        } else {
                            current
                        }
                    }

                    else -> pref.currentValue?.toString()
                }

                summary.replace("%s", entry ?: "")
            } else {
                summary
            }
            val map = mutableMapOf(
                "position" to index,
                "key" to key,
                "title" to pref.title?.toString(),
                "summary" to formattedSummary,
                "enabled" to pref.isEnabled,
                "type" to type,
                "value" to value
            )

            when (pref) {

                is ListPreference -> {
                    val entries = pref.entries?.map { it.toString() } ?: emptyList()
                    val values = pref.entryValues?.map { it.toString() } ?: emptyList()


                    map["entries"] = entries
                    map["entryValues"] = values
                }

                is MultiSelectListPreference -> {
                    val entries = pref.entries?.map { it.toString() } ?: emptyList()
                    val values = pref.entryValues?.map { it.toString() } ?: emptyList()

                    map["entries"] = entries
                    map["entryValues"] = values
                }
            }

            map
        }

        return encode(result)
    }

    override suspend fun saveSourcePreference(
        sourceId: String,
        key: String,
        value: String?
    ): Boolean {

        val screen = preferenceScreenMap[sourceId] ?: return false

        val pref = screen.preferences.find { it.key == key }
        if (pref == null) {
            return false
        }

        if (value == null) {
            return false
        }

        val payload = try {
            decode(value)
        } catch (_: Exception) {
            return false
        }

        val raw = payload["value"]

        val newValue: Any = when (pref.defaultValueType) {

            "String" -> raw as? String ?: ""
            "Boolean" -> raw as? Boolean ?: false
            "Set<String>" -> (raw as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet<String>()
            else -> {
                return false
            }
        }


        pref.saveNewValue(newValue)
        pref.callChangeListener(newValue)

        return true
    }
}

private fun SAnime.toMap() = mapOf(
    "title" to title, "url" to url, "cover" to thumbnail_url, "artist" to artist, "author" to author, "description" to description, "genre" to getGenres(), "status" to status
)