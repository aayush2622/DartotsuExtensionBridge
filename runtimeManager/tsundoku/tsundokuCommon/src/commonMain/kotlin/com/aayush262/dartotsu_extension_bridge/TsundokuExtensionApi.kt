package com.aayush262.dartotsu_extension_bridge


import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.aayush262.dartotsu_extension_bridge.network.Network.enableNetworking
import com.aayush262.dartotsu_extension_bridge.tsundoku.NovelSourceMethods
import com.aayush262.dartotsu_extension_bridge.tsundoku.TsundokuExtensionManager
import com.google.gson.Gson
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.online.HttpSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import kotlin.collections.component1
import kotlin.collections.component2
import kotlin.collections.plus

expect object TsundokuPlatformInit {
    fun initializeAndroid(context: Any)
    fun initializeDesktop(basePath: String)

    suspend fun saveSourcePreference(sourceId: String, key: String, value: String?): Boolean

    suspend fun getPreference(sourceId: String, isAnime: Boolean): String
}

class TsundokuExtensionApi : ExtensionApi, ExtensionBridgeApi {


    override fun initializeAndroid(context: Any) = TsundokuPlatformInit.initializeAndroid(context)

    override fun initializeDesktop(basePath: String) {
        TsundokuPlatformInit.initializeDesktop(basePath)
        initialize(CustomMethods())
    }

    override fun initClient(data: String) {
        val client = Injekt.get<NetworkHelper>()
        client.client = enableNetworking(data)
    }


    private val gson = Gson()

    private fun encode(data: Any?): String = gson.toJson(data)

    @Suppress("UNCHECKED_CAST")
    private fun decode(json: String): Map<String, Any?> = gson.fromJson(json, Map::class.java) as Map<String, Any?>

    override suspend fun getInstalledNovelExtensions(path: String?): String {
        path ?: return "[]"

        val result = withContext(Dispatchers.IO) {
            Injekt.get<TsundokuExtensionManager>().fetchInstalledNovelExtensions(path).flatMap { (ext, apkPath) ->
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
                        "itemType" to 2,
                        "isShared" to ext.isShared
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
            NovelSourceMethods(sourceId).getPopular(page)
        }

        return encode(
            mapOf(
                "list" to res.animes.map { it.toMap() }, "hasNextPage" to res.hasNextPage
            )
        )
    }

    override suspend fun getLatestUpdates(sourceId: String, isAnime: Boolean, page: Int): String {
        val res = withContext(Dispatchers.IO) {
            NovelSourceMethods(sourceId).getLatestUpdates(page)
        }

        return encode(
            mapOf(
                "list" to res.animes.map { it.toMap() }, "hasNextPage" to res.hasNextPage
            )
        )
    }

    override suspend fun search(sourceId: String, isAnime: Boolean, query: String, page: Int): String {
        val res = withContext(Dispatchers.IO) {
            NovelSourceMethods(sourceId).getSearchResults(query, page)
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

        val mediaSource = NovelSourceMethods(sourceId)
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


    override suspend fun getNovelContent(sourceId: String, episode: String): String {
        val epMap: Map<String, Any?> = decode(episode)

        val chapter = SChapter.create().apply {
            name = epMap["name"] as String
            url = epMap["url"] as String
            chapter_number = (epMap["episode_number"]?.toString()?.toFloat()) ?: 0f
        }

        val methods = NovelSourceMethods(sourceId)

        val pages = withContext(Dispatchers.IO) {
            methods.getPageList(chapter)
        }

        val pageText = withContext(Dispatchers.IO) {
            coroutineScope {
                pages.mapIndexed { index, page ->
                    async {
                        try {
                            val text = methods.fetchPageText(page)
                            text
                        } catch (e: Exception) {
                            throw e
                        }
                    }
                }.awaitAll()
            }
        }

        Logger.log("Fetched all pages. Total=${pageText.size}")

        val encoded = encode(pageText)

        Logger.log("Encoded result size=${encoded.length}")

        return encoded
    }

    override suspend fun saveSourcePreference(sourceId: String, key: String, value: String?): Boolean {
        return TsundokuPlatformInit.saveSourcePreference(sourceId, key, value)
    }

    override suspend fun getPreference(sourceId: String, isAnime: Boolean): String {
        return TsundokuPlatformInit.getPreference(sourceId, isAnime)
    }

    fun SAnime.toMap() = mapOf(
        "title" to title, "url" to url, "cover" to thumbnail_url, "artist" to artist, "author" to author, "description" to description, "genre" to getGenres(), "status" to status
    )
}


