package com.aayush262.dartotsu_extension_bridge.aniyomi


import android.content.Context
import com.aayush262.dartotsu_extension_bridge.LogLevel
import com.aayush262.dartotsu_extension_bridge.Logger
import eu.kanade.tachiyomi.extension.anime.model.AnimeExtension
import eu.kanade.tachiyomi.extension.manga.model.MangaExtension

class AniyomiExtensionManager(var context: Context) {
    lateinit var installedAnimeExtensions: List<AnimeExtension.Installed>
    lateinit var installedMangaExtensions: List<MangaExtension.Installed>

    fun fetchInstalledAnimeExtensions(path: String): List<AnimeExtension.Installed> = runCatching {
        return AnimeExtensionLoader.loadExtensions(path).apply { installedAnimeExtensions = this }
    }.getOrElse { e ->
        Logger.log( "Failed to load anime extensions: ${e.message}",LogLevel.ERROR)
        emptyList()
    }
    fun fetchInstalledMangaExtensions(path: String): List<MangaExtension.Installed> = runCatching {
        return MangaExtensionLoader.loadExtensions(path).apply { installedMangaExtensions = this }
    }.getOrElse { e ->
        Logger.log( "Failed to load manga extensions: ${e.message}",LogLevel.ERROR)
        emptyList()
    }

}