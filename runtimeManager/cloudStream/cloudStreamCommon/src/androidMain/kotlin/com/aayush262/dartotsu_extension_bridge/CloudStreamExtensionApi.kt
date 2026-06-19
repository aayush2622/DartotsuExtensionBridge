package com.aayush262.dartotsu_extension_bridge

import android.content.Context
import com.aayush262.dartotsu_extension_bridge.cloudStream.CloudStreamSourceMethods
import com.aayush262.dartotsu_extension_bridge.cloudStream.ExtensionLoader
import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import com.aayush262.dartotsu_extension_bridge.network.Network.enableNetworking
import com.lagradost.cloudstream3.APIHolder.allProviders
import com.lagradost.cloudstream3.APIHolder.mapper
import com.lagradost.cloudstream3.AcraApplication
import com.lagradost.cloudstream3.CloudStreamApp
import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.app
import com.lagradost.cloudstream3.utils.DataStore

actual class CloudStreamExtensionApi : ExtensionApi, ExtensionBridgeApi {
    override fun initClient(data: String) {
        app.baseClient = enableNetworking(data)
    }

    override fun initializeAndroid(context: Any) {
        DataStore.init(context as Context)
        AcraApplication.context = context
        CloudStreamApp.context = context

        super.initializeAndroid(context)
    }


    private fun provider(sourceId: String): MainAPI {
        return allProviders.firstOrNull {
            it.name == sourceId || it.javaClass.simpleName == sourceId
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
                    "supportsLatest" to true
                )
            }
        )
    }

    override suspend fun getInstalledMangaExtensions(path: String?): String {
        return "[]"
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
        return mapper.writeValueAsString(
            methods(sourceId).getDetails(media)
        )
    }

    override suspend fun getVideoList(
        sourceId: String,
        isAnime: Boolean,
        episode: String
    ): String {
        return mapper.writeValueAsString(
            methods(sourceId).loadLinks(episode)
        )
    }

    override suspend fun getPageList(
        sourceId: String,
        isAnime: Boolean,
        episode: String
    ): String {
        return "[]"
    }

    override suspend fun getPreference(
        sourceId: String,
        isAnime: Boolean
    ): String {
        return "[]"
    }

    override suspend fun saveSourcePreference(
        sourceId: String,
        key: String,
        value: String?
    ): Boolean {
        return false
    }


}