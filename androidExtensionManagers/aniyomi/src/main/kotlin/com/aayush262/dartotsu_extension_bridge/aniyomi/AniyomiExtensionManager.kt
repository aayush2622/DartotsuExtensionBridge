package com.aayush262.dartotsu_extension_bridge.aniyomi

import android.content.Context
import com.aayush262.dartotsu_extension_bridge.LogLevel
import com.aayush262.dartotsu_extension_bridge.Logger
import com.aayush262.dartotsu_extension_bridge.aniyomi.models.ExtensionJsonObject
import com.aayush262.dartotsu_extension_bridge.aniyomi.models.toAnimeExtensions
import com.aayush262.dartotsu_extension_bridge.aniyomi.models.toMangaExtensions
import eu.kanade.tachiyomi.extension.anime.model.AnimeExtension
import eu.kanade.tachiyomi.extension.manga.model.MangaExtension
import eu.kanade.tachiyomi.extension.manga.model.MangaLoadResult
import eu.kanade.tachiyomi.extension.util.ExtensionLoader
import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.network.awaitSuccess
import eu.kanade.tachiyomi.network.parseAs
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import uy.kohesive.injekt.injectLazy

class AniyomiExtensionManager(var context: Context) {
    lateinit var installedAnimeExtensions: List<AnimeExtension.Installed>
    lateinit var installedMangaExtensions: List<MangaExtension.Installed>

    fun fetchInstalledAnimeExtensions(path: String?): List<AnimeExtension.Installed> = runCatching {
        AnimeExtensionLoader.loadExtensions(context,path).apply { installedAnimeExtensions = this }
    }.getOrElse { e ->
        Logger.log( "Failed to load anime extensions: ${e.message}",LogLevel.ERROR)
        emptyList()
    }
    fun fetchInstalledMangaExtensions(path: String?): List<MangaExtension.Installed> = runCatching {
        MangaExtensionLoader.loadExtensions(context,path).apply { installedMangaExtensions = this }
    }.getOrElse { e ->
        Logger.log( "Failed to load manga extensions: ${e.message}",LogLevel.ERROR)
        emptyList()
    }

}