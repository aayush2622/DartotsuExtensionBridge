package com.aayush262.dartotsu_extension_bridge

import com.aayush262.dartotsu_extension_bridge.cloudStream.CloudStreamSourceMethods
import com.aayush262.dartotsu_extension_bridge.cloudStream.ExtensionLoader
import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import com.aayush262.dartotsu_extension_bridge.network.Network.enableNetworking
import com.google.gson.Gson
import com.lagradost.cloudstream3.APIHolder.allProviders
import com.lagradost.cloudstream3.APIHolder.mapper
import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.app
import kotlin.collections.get


expect object PlatformInit {
    fun initializeAndroid(context: Any)
    fun initializeDesktop(basePath: String)
}

class CloudStreamExtensionApi : ExtensionApi, ExtensionBridgeApi{

    override fun initializeAndroid(context: Any) =
        PlatformInit.initializeAndroid(context)

    override fun initializeDesktop(basePath: String) {
        PlatformInit.initializeDesktop(basePath)
        initialize(CustomMethods())
    }

    override fun initClient(data: String) {
        app.baseClient = enableNetworking(data)
    }

    private val gson = Gson()

    @Suppress("UNCHECKED_CAST")
    private fun decode(json: String): Map<String, Any?> =
        gson.fromJson(json, Map::class.java) as Map<String, Any?>
    private fun provider(sourceId: String): MainAPI {
        return allProviders.firstOrNull {
            it.name.equals(sourceId, ignoreCase = true) ||
                    it.javaClass.simpleName.equals(sourceId, ignoreCase = true) ||
                    it.javaClass.name.equals(sourceId, ignoreCase = true)
        } ?: error("Provider not found: $sourceId")
    }
    private fun methods(sourceId: String) =
        CloudStreamSourceMethods(provider(sourceId))

    override suspend fun getInstalledAnimeExtensions(path: String?): String {
        ExtensionLoader.unloadExtensions()
        ExtensionLoader.loadExtensions(path ?: return "[]")
        return mapper.writeValueAsString(
            allProviders.map {
                mapOf(
                    "id" to it.name,
                    "name" to it.name,
                    "lang" to it.lang,
                    "supportsLatest" to true,
                    "sourcePlugin" to it.sourcePlugin,
                    "baseUrl" to it.mainUrl,
                    "iconUrl" to "https://avatars.githubusercontent.com/u/110591699?s=48&v=4",
                    "itemType" to 1,
                    "version" to ExtensionLoader.plugins[it.sourcePlugin]?.manifest?.version.toString()
                )
            }
        )
    }

    override suspend fun getPopular(
        sourceId: String,
        isAnime: Boolean,
        page: Int
    ): String {
        return mapper.writeValueAsString(
            methods(sourceId).search("", page)
        )
    }

    override suspend fun getLatestUpdates(
        sourceId: String,
        isAnime: Boolean,
        page: Int
    ): String {
        return mapper.writeValueAsString(
            methods(sourceId).search("", page)
        )
    }

    override suspend fun search(
        sourceId: String,
        isAnime: Boolean,
        query: String,
        page: Int
    ): String {
        return mapper.writeValueAsString(
            methods(sourceId).search(query, page)
        )
    }

    override suspend fun getDetail(
        sourceId: String,
        isAnime: Boolean,
        media: String
    ): String {
        val mediaMap: Map<String, Any?> = decode(media)
        return mapper.writeValueAsString(
            methods(sourceId).getDetails(mediaMap["url"] as String)
        )
    }

    override suspend fun getVideoList(
        sourceId: String,
        isAnime: Boolean,
        episode: String
    ): String {
        val epMap = decode(episode)
        return mapper.writeValueAsString(
            methods(sourceId).loadLinks(epMap["url"] as String)
        )
    }
}