package com.aayush262.dartotsu_extension_bridge.kotatsu

expect object KotatsuExtensionLoader {
    suspend fun loadExtensions(folderPath: String?): List<Map<String, Any?>>

    suspend fun getPopular(sourceId: String, page: Int): Map<String, Any?>

    suspend fun getLatestUpdates(sourceId: String, page: Int): Map<String, Any?>

    suspend fun search(sourceId: String, query: String, page: Int): Map<String, Any?>

    suspend fun getDetails(sourceId: String, url: String, title: String, cover: String): Map<String, Any?>

    suspend fun getPageList(sourceId: String, url: String, name: String): List<Map<String, Any?>>
}
