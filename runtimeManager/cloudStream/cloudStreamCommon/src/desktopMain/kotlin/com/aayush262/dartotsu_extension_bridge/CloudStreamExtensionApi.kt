package com.aayush262.dartotsu_extension_bridge

import android.app.Application
import android.content.Context
import android.os.Looper
import com.aayush262.dartotsu_extension_bridge.cloudStream.CloudStreamSourceMethods
import com.aayush262.dartotsu_extension_bridge.cloudStream.ExtensionLoader
import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.aayush262.dartotsu_extension_bridge.network.Network.enableNetworking
import com.lagradost.cloudstream3.APIHolder.allProviders
import com.lagradost.cloudstream3.APIHolder.mapper
import com.lagradost.cloudstream3.AcraApplication
import com.lagradost.cloudstream3.CloudStreamApp
import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.app
import com.lagradost.cloudstream3.utils.DataStore
import org.koin.core.context.GlobalContext
import org.koin.core.context.startKoin
import org.koin.dsl.module
import org.koin.mp.KoinPlatformTools
import xyz.nulldev.androidcompat.androidimpl.CustomContext
import xyz.nulldev.androidcompat.xyz.nulldev.androidcompat.androidCompatModule
import java.io.File
import kotlin.getValue

actual class CloudStreamExtensionApi : ExtensionApi, ExtensionBridgeApi {
    override fun initClient(data: String) {
        app.baseClient = enableNetworking(data)
    }

    override fun initializeDesktop(basePath: String) {
        val root = File(basePath).also(File::mkdirs)
        CommonDesktopApi.init(root.absolutePath)

        if (GlobalContext.getOrNull() != null) {
            Logger.log("Koin already started")
            return
        }

        val application = object : Application() {}

        startMainLooper()

        startKoin {
            modules(
                module {
                    single<Application> { application }
                },
                androidCompatModule(root),
            )
        }

        val customContext: CustomContext =
            KoinPlatformTools.defaultContext().get().get()

        application.attach(customContext)
        application.onCreate()

        DataStore.init(application)
        AcraApplication.context = application
        CloudStreamApp.context = application

        super.initializeDesktop(basePath)
    }

    private fun startMainLooper() {
        Thread {
            Looper.prepareMainLooper()
            Looper.loop()
        }.apply {
            name = "AndroidMainLooper"
            isDaemon = true
            start()
        }
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
                    "supportsLatest" to true,
                    "sourcePlugin" to it.sourcePlugin,
                    "baseUrl" to it.mainUrl,
                    "iconUrl" to "https://avatars.githubusercontent.com/u/110591699?s=48&v=4"
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