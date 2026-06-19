
package com.aayush262.dartotsu_extension_bridge.aniyomi

import eu.kanade.tachiyomi.extension.manga.model.MangaExtension

expect object  MangaExtensionLoader {
    fun loadExtensions(path: String): Map<MangaExtension.Installed, String>
}


