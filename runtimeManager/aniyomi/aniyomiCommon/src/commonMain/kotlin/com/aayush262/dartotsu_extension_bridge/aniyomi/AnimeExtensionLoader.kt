package com.aayush262.dartotsu_extension_bridge.aniyomi

import eu.kanade.tachiyomi.extension.anime.model.AnimeExtension

expect object AnimeExtensionLoader {
    fun loadExtensions(
        path: String
    ): Map<AnimeExtension.Installed, String>
}