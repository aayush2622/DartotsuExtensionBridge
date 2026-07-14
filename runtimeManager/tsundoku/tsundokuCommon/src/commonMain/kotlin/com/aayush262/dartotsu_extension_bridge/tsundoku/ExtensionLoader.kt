package com.aayush262.dartotsu_extension_bridge.tsundoku

import eu.kanade.tachiyomi.extension.manga.model.MangaExtension

expect object  NovelExtensionLoader {
    fun loadExtensions(path: String): Map<MangaExtension.Installed, String>
}
