package com.aayush262.dartotsu_extension_bridge

import androidx.core.net.toUri
import com.aayush262.dartotsu_extension_bridge.aniyomi.AnimeSourceMethods
import com.aayush262.dartotsu_extension_bridge.aniyomi.AniyomiExtensionManager
import com.aayush262.dartotsu_extension_bridge.aniyomi.MangaSourceMethods
import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import com.aayush262.dartotsu_extension_bridge.network.Network.enableNetworking
import com.google.gson.Gson
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.online.HttpSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import kotlin.collections.component1
import kotlin.collections.component2
import kotlin.collections.plus
import kotlin.collections.toMap


expect object PlatformInit {
    fun initializeAndroid(context: Any)
    fun initializeDesktop(basePath: String)

    suspend fun saveSourcePreference(sourceId: String, key: String, value: String?): Boolean

    suspend fun getPreference(sourceId: String, isAnime: Boolean): String
}

class AniyomiExtensionApi : ExtensionApi, ExtensionBridgeApi {


    override fun initializeAndroid(context: Any) = PlatformInit.initializeAndroid(context)

    override fun initializeDesktop(basePath: String) {
        PlatformInit.initializeDesktop(basePath)
        initialize(CustomMethods())
    }

    override fun initClient(data: String) {
        val helper = Injekt.get<NetworkHelper>()
        val base = helper.client
        val custom = enableNetworking(data)

        val builder = custom.newBuilder()

        base.cache?.let { builder.cache(it) }

        base.networkInterceptors.forEach {
            builder.addNetworkInterceptor(it)
        }
        base.interceptors.forEach {
            builder.addInterceptor(it)
        }
        builder.cookieJar(base.cookieJar)
        helper.client = builder.build()
    }

    private fun media(sourceId: String, isAnime: Boolean) = if (isAnime) AnimeSourceMethods(sourceId)
    else MangaSourceMethods(sourceId)

    private val gson = Gson()

    private fun encode(data: Any?): String = gson.toJson(data)

    @Suppress("UNCHECKED_CAST")
    private fun decode(json: String): Map<String, Any?> = gson.fromJson(json, Map::class.java) as Map<String, Any?>

    override suspend fun getInstalledAnimeExtensions(path: String?): String {
        path ?: return "[]"

        val result = withContext(Dispatchers.IO) {
            Injekt.get<AniyomiExtensionManager>().fetchInstalledAnimeExtensions(path).flatMap { (ext, apkPath) ->
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
                            "apkPath" to apkPath,
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
            Injekt.get<AniyomiExtensionManager>().fetchInstalledMangaExtensions(path).flatMap { (ext, apkPath) ->
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
                            "apkPath" to apkPath,
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
                "list" to res.animes.map { it.toMap() }, "hasNextPage" to res.hasNextPage
            )
        )
    }

    override suspend fun getLatestUpdates(sourceId: String, isAnime: Boolean, page: Int): String {
        val res = withContext(Dispatchers.IO) {
            media(sourceId, isAnime).getLatestUpdates(page)
        }

        return encode(
            mapOf(
                "list" to res.animes.map { it.toMap() }, "hasNextPage" to res.hasNextPage
            )
        )
    }

    override suspend fun search(sourceId: String, isAnime: Boolean, query: String, page: Int): String {
        val res = withContext(Dispatchers.IO) {
            media(sourceId, isAnime).getSearchResults(query, page)
        }

        return encode(
            mapOf(
                "list" to res.animes.map { it.toMap() }, "hasNextPage" to res.hasNextPage
            )
        )
    }


    override suspend fun getDetail(
        sourceId: String, isAnime: Boolean, media: String
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
        val data = mediaSource.getDetails(anime)
        val details = data.first
        val episodes = data.second
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
                    "name" to it.name, "url" to it.url, "date_upload" to it.date_upload, "episode_number" to it.episode_number, "scanlator" to it.scanlator
                )
            })

        return@withContext encode(result)
    }


    override suspend fun getVideoList(
        sourceId: String, isAnime: Boolean, episode: String
    ): String = withContext(Dispatchers.IO) {

        val epMap = decode(episode)

        val ep = SEpisode.create().apply {
            name = epMap["name"] as String
            url = epMap["url"] as String
            episode_number = (epMap["episode_number"] as? Double)?.toFloat() ?: 0f
            scanlator = epMap["scanlator"] as? String
        }

        val result = media(sourceId, isAnime).getVideoList(ep).map {
            mapOf("title" to it.videoTitle, "url" to it.videoUrl, "quality" to it.resolution, "headers" to it.headers?.toMap(), "subtitles" to it.subtitleTracks.map { t ->
                mapOf("file" to t.url, "label" to t.lang)
            }, "audios" to it.audioTracks.map { t ->
                mapOf("file" to t.url, "label" to t.lang)
            }, "timestamps" to it.timestamps.map { t ->
                mapOf(
                    "name" to t.name, "startTime" to t.start, "endTime" to t.end
                )
            })
        }

        return@withContext encode(result)
    }

    override suspend fun getPageList(sourceId: String, isAnime: Boolean, episode: String): String {
        val epMap: Map<String, Any?> = decode(episode)

        val chapter = SChapter.create().apply {
            name = epMap["name"] as String
            url = epMap["url"] as String
        }
        val source = media(sourceId, isAnime)

        val pages = withContext(Dispatchers.IO) {
            source.getPageList(chapter)
        }

        return encode(
            pages.map { it.toPayload(source.baseUrl ?: "") })
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

    override suspend fun saveSourcePreference(sourceId: String, key: String, value: String?): Boolean {
        return PlatformInit.saveSourcePreference(sourceId, key, value)
    }

    override suspend fun getPreference(sourceId: String, isAnime: Boolean): String {
        return PlatformInit.getPreference(sourceId, isAnime)
    }
}

private fun SAnime.toMap() = mapOf(
    "title" to title, "url" to url, "cover" to thumbnail_url, "artist" to artist, "author" to author, "description" to description, "genre" to getGenres(), "status" to status
)
