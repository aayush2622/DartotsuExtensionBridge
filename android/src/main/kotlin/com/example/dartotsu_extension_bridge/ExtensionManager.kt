package com.example.dartotsu_extension_bridge

import android.content.Context
import eu.kanade.tachiyomi.animesource.AnimeSource
import eu.kanade.tachiyomi.extension.anime.model.AnimeExtension
import eu.kanade.tachiyomi.extension.anime.model.AnimeLoadResult
import eu.kanade.tachiyomi.extension.util.ExtensionLoader

class ExtensionManager(var context: Context) {

    fun getInstalledExtensions(): List<AnimeExtension>? {
        var sources = ExtensionLoader.loadAnimeExtensions(context)
        var installedSource = sources.filterIsInstance<AnimeLoadResult.Success>().map { it.extension }
        return installedSource
    }

}