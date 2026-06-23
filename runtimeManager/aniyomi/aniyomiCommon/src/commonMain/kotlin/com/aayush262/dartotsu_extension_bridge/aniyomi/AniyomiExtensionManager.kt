package com.aayush262.dartotsu_extension_bridge.aniyomi


import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import eu.kanade.tachiyomi.extension.anime.model.AnimeExtension
import eu.kanade.tachiyomi.extension.manga.model.MangaExtension

class AniyomiExtensionManager {

    lateinit var installedAnimeExtensions: Map<AnimeExtension.Installed, String>
    lateinit var installedMangaExtensions: Map<MangaExtension.Installed, String>

    fun fetchInstalledAnimeExtensions(
        path: String
    ): Map<AnimeExtension.Installed, String> = runCatching {

        AnimeExtensionLoader.loadExtensions(path).apply {
            installedAnimeExtensions = this
        }

    }.getOrElse { e ->
        Logger.log(
            "Failed to load anime extensions:",
            e,
            LogLevel.ERROR,

        )
        emptyMap()
    }

    fun fetchInstalledMangaExtensions(
        path: String
    ): Map<MangaExtension.Installed, String> = runCatching {

        MangaExtensionLoader.loadExtensions(path).apply {
            installedMangaExtensions = this
        }

    }.getOrElse { e ->
        Logger.log(
            "Failed to load manga extensions:",
            e,
            LogLevel.ERROR
        )
        emptyMap()
    }
}