package com.aayush262.dartotsu_extension_bridge

import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import com.aayush262.dartotsu_extension_bridge.ireader.ExtensionLoader
import com.google.gson.Gson
import ireader.core.source.CatalogSource
import ireader.core.source.model.ChapterInfo
import ireader.core.source.model.Filter
import ireader.core.source.model.ImageBase64
import ireader.core.source.model.ImageUrl
import ireader.core.source.model.Listing
import ireader.core.source.model.MangaInfo
import ireader.core.source.model.MovieUrl
import ireader.core.source.model.Page
import ireader.core.source.model.PageUrl
import ireader.core.source.model.Subtitle
import ireader.core.source.model.Text
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

expect object PlatformInit {
    fun initializeAndroid(context: Any)
    fun initializeDesktop(basePath: String)
}

class IReaderExtensionApi : ExtensionApi, ExtensionBridgeApi {

    override fun initializeAndroid(context: Any) = PlatformInit.initializeAndroid(context)

    override fun initializeDesktop(basePath: String) {
        PlatformInit.initializeDesktop(basePath)
        initialize(CustomMethods())
    }

    private val gson = Gson()

    private fun encode(data: Any?): String = gson.toJson(data)

    @Suppress("UNCHECKED_CAST")
    private fun decode(json: String): Map<String, Any?> = gson.fromJson(json, Map::class.java) as Map<String, Any?>

    private fun source(id: String): CatalogSource {
        return ExtensionLoader.plugins.values.first {
            it.id.toString() == id
        }
    }

    private fun CatalogSource.findListing(vararg names: String): Listing? {
        val listings = getListings()

        return listings.firstOrNull { listing ->
            names.any { it.equals(listing.name, true) }
        } ?: listings.firstOrNull()
    }

    private fun MangaInfo.toMap() = mapOf(
        "title" to title, "url" to key, "cover" to cover, "artist" to artist, "author" to author, "description" to description, "genre" to genres, "status" to status
    )


    override suspend fun getInstalledNovelExtensions(path: String?): String {

        path ?: return "[]"

        return encode(
            ExtensionLoader.loadExtensions(path).map {

                mapOf(
                    "id" to it.source.id,
                    "name" to it.source.name,
                    "baseUrl" to it.baseUrl,
                    "lang" to it.source.lang,
                    "version" to it.versionName,
                    "pkgName" to it.packageName,
                    "apkPath" to it.apkPath,
                    "description" to it.description,
                    "iconUrl" to it.icon,
                    "itemType" to 2
                )
            })
    }

    override suspend fun getPopular(
        sourceId: String, isAnime: Boolean, page: Int
    ): String {

        val src = source(sourceId)

        val listing = src.findListing(
            "Popular", "Trending", "Most Popular"
        )

        val result = withContext(Dispatchers.IO) {
            src.getMangaList(listing, page)
        }

        return encode(
            mapOf(
                "list" to result.mangas.map {
                    it.toMap()
                }, "hasNextPage" to result.hasNextPage
            )
        )
    }

    override suspend fun getLatestUpdates(
        sourceId: String, isAnime: Boolean, page: Int
    ): String {

        val src = source(sourceId)

        val listing = src.findListing(
            "Latest", "Latest Updates", "Recent"
        )

        val result = withContext(Dispatchers.IO) {
            src.getMangaList(listing, page)
        }

        return encode(
            mapOf(
                "list" to result.mangas.map {
                    it.toMap()
                }, "hasNextPage" to result.hasNextPage
            )
        )
    }

    override suspend fun search(
        sourceId: String, isAnime: Boolean, query: String, page: Int
    ): String {

        val src = source(sourceId)

        val result = withContext(Dispatchers.IO) {
            src.getMangaList(
                listOf(
                    Filter.Title(query)
                ), page
            )
        }

        return encode(
            mapOf(
                "list" to result.mangas.map {
                    it.toMap()
                }, "hasNextPage" to result.hasNextPage
            )
        )
    }

    override suspend fun getDetail(
        sourceId: String, isAnime: Boolean, media: String
    ): String = withContext(Dispatchers.IO) {

        val mediaMap = decode(media)

        val manga = MangaInfo(
            key = mediaMap["url"] as String,
            title = mediaMap["title"] as String,
            artist = mediaMap["artist"] as? String ?: "",
            author = mediaMap["author"] as? String ?: "",
            description = mediaMap["description"] as? String ?: "",
            genres = (mediaMap["genre"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
            status = (mediaMap["status"] as? Number)?.toLong() ?: MangaInfo.UNKNOWN,
            cover = mediaMap["cover"] as? String ?: ""
        )

        val src = source(sourceId)

        val details = src.getMangaDetails(
            manga, emptyList()
        )

        val chapters = src.getChapterList(
            manga, emptyList()
        )

        val result = mapOf(
            "title" to details.title,
            "url" to details.key,
            "cover" to details.cover,
            "artist" to details.artist,
            "author" to details.author,
            "description" to details.description,
            "genre" to details.genres,
            "status" to details.status,
            "episodes" to chapters.map {
                mapOf(
                    "name" to it.name, "url" to it.key, "date_upload" to it.dateUpload, "episode_number" to it.number, "scanlator" to it.scanlator
                )
            })

        encode(result)
    }

    override suspend fun getPageList(
        sourceId: String, isAnime: Boolean, episode: String
    ): String {

        val ep = decode(episode)

        val chapter = ChapterInfo(
            key = ep["url"] as String,
            name = ep["name"] as String,
            dateUpload = (ep["date_upload"] as? Number)?.toLong() ?: 0,
            number = (ep["episode_number"] as? Number)?.toFloat() ?: -1f,
            scanlator = ep["scanlator"] as? String ?: ""
        )

        val pages = withContext(Dispatchers.IO) {
            source(sourceId).getPageList(
                chapter, emptyList()
            )
        }

        return encode(
            mapOf(
                "html" to toHtml(pages)
            )
        )
    }
    fun toHtml(pages: List<Page>): String =
        buildString {
            for (page in pages) {
                when (page) {
                    is Text ->
                        append("<p>${escapeHtml(page.text)}</p>\n")

                    is ImageUrl ->
                        append("<img src=\"${page.url}\" />\n")

                    is ImageBase64 ->
                        append("<img src=\"data:image/png;base64,${page.data}\" />\n")

                    is MovieUrl ->
                        append("<video controls src=\"${page.url}\"></video>\n")

                    is Subtitle -> {
                        // optional
                    }

                    is PageUrl ->
                        append("<img src=\"${page.url}\" />\n")
                }
            }
        }
    fun escapeHtml(text: String): String =
        text.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")

    override suspend fun getPreference(sourceId: String, isAnime: Boolean): String {
        TODO("Not yet implemented")
    }

    override suspend fun saveSourcePreference(sourceId: String, key: String, value: String?): Boolean {
        TODO("Not yet implemented")
    }

    override fun initClient(data: String) {
        TODO("Not yet implemented")
    }

}