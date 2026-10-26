package com.aayush262.dartotsu_extension_bridge

import com.aayush262.dartotsu_extension_bridge.cloudStream.CloudStreamSourceMethods
import com.aayush262.dartotsu_extension_bridge.cloudStream.ExtensionLoader
import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import com.aayush262.dartotsu_extension_bridge.common.ExtensionLoadStatus
import com.aayush262.dartotsu_extension_bridge.network.Network
import com.lagradost.cloudstream3.bridgeClient
import com.google.gson.Gson
import com.aayush262.dartotsu_extension_bridge.cloudStream.SourcePreferences
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import com.lagradost.cloudstream3.APIHolder.allProviders
import com.lagradost.cloudstream3.APIHolder.mapper
import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.app
import kotlin.collections.get


expect object CloudStreamPlatformInit {
    fun initializeAndroid(context: Any)
    fun initializeDesktop(basePath: String)
}

class CloudStreamExtensionApi : ExtensionApi, ExtensionBridgeApi, ExtensionLoadStatus {

    override fun initializeAndroid(context: Any) =
        CloudStreamPlatformInit.initializeAndroid(context)

    override fun initializeDesktop(basePath: String) {
        CloudStreamPlatformInit.initializeDesktop(basePath)
        initialize(CustomMethods())
        preloadPath = java.io.File(basePath, "extensions/Anime").path
    }

    // Plugins are prepared once the app's network settings are in (the first initClient), so a
    // call made before the app has asked for the list finds its provider, or waits for it.
    @Volatile
    private var preloadPath: String? = null

    override fun initClient(data: String) {
        Network.configure(data)
        app.baseClient = bridgeClient()
        PluginRequests.refresh()
        preloadPath?.let {
            preloadPath = null
            ExtensionLoader.preloadExtensions(it)
        }
    }

    private val gson = Gson()

    @Suppress("UNCHECKED_CAST")
    private fun decode(json: String): Map<String, Any?> =
        gson.fromJson(json, Map::class.java) as Map<String, Any?>
    private fun findProvider(sourceId: String): MainAPI? =
        allProviders.toList().firstOrNull {
            it.name.equals(sourceId, ignoreCase = true) ||
                    it.javaClass.simpleName.equals(sourceId, ignoreCase = true) ||
                    it.javaClass.name.equals(sourceId, ignoreCase = true)
        }

    /** A provider whose plugin is still being prepared shows up shortly: wait for it instead of failing. */
    private suspend fun provider(sourceId: String): MainAPI {
        findProvider(sourceId)?.let { return it }
        val deadline = System.currentTimeMillis() + PROVIDER_WAIT_MS
        while (ExtensionLoader.pendingExtensions() > 0 && System.currentTimeMillis() < deadline) {
            delay(250)
            findProvider(sourceId)?.let { return it }
        }
        error("Provider not found: $sourceId")
    }

    private suspend fun methods(sourceId: String) =
        CloudStreamSourceMethods(provider(sourceId))

    override fun pendingExtensions(): Int = ExtensionLoader.pendingExtensions()

    override suspend fun getInstalledAnimeExtensions(path: String?): String {
        val dir = path ?: return "[]"
        withContext(Dispatchers.IO) { ExtensionLoader.refreshExtensions(dir, LIST_WAIT_MS) }
        return mapper.writeValueAsString(
            allProviders.toList().map {
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

    private companion object {
        const val LIST_WAIT_MS = 12_000L
        const val PROVIDER_WAIT_MS = 180_000L
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
        page: Int,
        filters: String
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

    override suspend fun getPreference(sourceId: String, isAnime: Boolean): String =
        withContext(Dispatchers.IO) { SourcePreferences.get(provider(sourceId)) }

    override suspend fun saveSourcePreference(sourceId: String, key: String, value: String?): Boolean =
        withContext(Dispatchers.IO) { SourcePreferences.save(provider(sourceId), key, value) }

    override suspend fun releaseCachedJar(jarPath: String): Boolean {
        ExtensionLoader.releaseCachedJar(jarPath)
        return true
    }
}
