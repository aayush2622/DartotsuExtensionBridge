package com.aayush262.dartotsu_extension_bridge.tsundoku



import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import eu.kanade.tachiyomi.extension.manga.model.MangaExtension
class TsundokuExtensionManager {


    lateinit var installedNovelExtensions: Map<MangaExtension.Installed, String>



    fun fetchInstalledNovelExtensions(
        path: String
    ): Map<MangaExtension.Installed, String> = runCatching {

        NovelExtensionLoader.loadExtensions(path).apply {
            installedNovelExtensions= this
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