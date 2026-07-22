package com.aayush262.dartotsu_extension_bridge.kotatsu

import com.aayush262.dartotsu_extension_bridge.ExtensionApi
import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import com.google.gson.Gson
expect object PlatformInit {
    fun initializeAndroid(context: Any)
    fun initializeDesktop(basePath: String)
}

class KotatsuExtensionApi : ExtensionApi, ExtensionBridgeApi {

    override fun initializeAndroid(context: Any) {
        PlatformInit.initializeAndroid(context)
    }

    override fun initializeDesktop(basePath: String) {
        PlatformInit.initializeDesktop(basePath)
    }

    override fun initClient(data: String) {
        // reuse your networking bridge if desired
    }

    private val gson = Gson()

    private fun encode(data: Any?): String = gson.toJson(data)

    override suspend fun getInstalledAnimeExtensions(path: String?): String {
        return "[]"
    }

    override suspend fun getInstalledMangaExtensions(path: String?): String {
        path ?: return "[]"
        return encode(
            KotatsuExtensionLoader.loadExtensions(path)
        )
    }

    override suspend fun getPopular(
        sourceId: String,
        isAnime: Boolean,
        page: Int,
    ): String {
        return encode(
            KotatsuExtensionLoader.getPopular(sourceId, page)
        )
    }

    override suspend fun getLatestUpdates(
        sourceId: String,
        isAnime: Boolean,
        page: Int,
    ): String {
        return encode(
            KotatsuExtensionLoader.getLatestUpdates(sourceId, page)
        )
    }

    override suspend fun search(
        sourceId: String,
        isAnime: Boolean,
        query: String,
        page: Int,
    ): String {
        return encode(
            KotatsuExtensionLoader.search(
                sourceId,
                query,
                page,
            )
        )
    }

    override suspend fun getDetail(
        sourceId: String,
        isAnime: Boolean,
        media: String,
    ): String {
        val obj = gson.fromJson(media, Map::class.java) as Map<*, *>

        return encode(
            KotatsuExtensionLoader.getDetails(
                sourceId,
                obj["url"] as String,
                obj["title"] as String,
                obj["cover"] as? String ?: "",
            )
        )
    }


    override suspend fun getPageList(
        sourceId: String,
        isAnime: Boolean,
        episode: String,
    ): String {

        val obj = gson.fromJson(episode, Map::class.java) as Map<*, *>

        return encode(
            KotatsuExtensionLoader.getPageList(
                sourceId,
                obj["url"] as String,
                obj["name"] as String,
            )
        )
    }

}