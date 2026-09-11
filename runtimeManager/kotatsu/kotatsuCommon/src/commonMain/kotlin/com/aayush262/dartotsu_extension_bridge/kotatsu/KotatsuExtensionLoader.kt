package com.aayush262.dartotsu_extension_bridge.kotatsu

/**
 * Loads the shared Kotatsu parsers jar and runs [org.koitharu.kotatsu.parsers.MangaParser]
 * calls against it.
 *
 * Android's implementation loads the jar's DEX bytecode directly via
 * `dalvik.system.DexClassLoader` (a real Dalvik/ART runtime is available).
 * Desktop has no such runtime, so its implementation runs the jar through
 * the same dex2jar conversion the other four JVM-sidecar backends already
 * use (see `util.PackageTools.dex2jar` in commonDesktopLib) and loads the
 * converted jar with a normal classloader instead.
 */
expect object KotatsuExtensionLoader {
    suspend fun loadExtensions(folderPath: String?): List<Map<String, Any?>>

    suspend fun getPopular(sourceId: String, page: Int): Map<String, Any?>

    suspend fun getLatestUpdates(sourceId: String, page: Int): Map<String, Any?>

    suspend fun search(sourceId: String, query: String, page: Int): Map<String, Any?>

    suspend fun getDetails(sourceId: String, url: String, title: String, cover: String): Map<String, Any?>

    suspend fun getPageList(sourceId: String, url: String, name: String): List<Map<String, Any?>>
}
