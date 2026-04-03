package com.aayush262.dartotsu_extension_bridge

interface ExtensionApi {

    fun initializeAndroid(context: Any){}
    fun initializeDesktop(basePath: String){}
    suspend fun getInstalledAnimeExtensions(path: String?): String

    suspend fun getInstalledMangaExtensions(path: String?): String

    suspend fun getPopular(
        sourceId: String, isAnime: Boolean, page: Int
    ): String

    suspend fun getLatestUpdates(
        sourceId: String, isAnime: Boolean, page: Int
    ): String

    suspend fun search(
        sourceId: String, isAnime: Boolean, query: String, page: Int
    ): String

    suspend fun getDetail(
        sourceId: String, isAnime: Boolean, media: String
    ): String

    suspend fun getVideoList(
        sourceId: String, isAnime: Boolean, episode: String
    ): String

    suspend fun getPageList(
        sourceId: String, isAnime: Boolean, episode: String
    ): String

    suspend fun getPreference(
        sourceId: String, isAnime: Boolean
    ): String

    suspend fun saveSourcePreference(
        sourceId: String, key: String, value: String?
    ): Boolean
}