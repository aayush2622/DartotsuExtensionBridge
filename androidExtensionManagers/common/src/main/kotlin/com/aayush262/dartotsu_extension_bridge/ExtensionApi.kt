package com.aayush262.dartotsu_extension_bridge

import android.content.Context


interface ExtensionApi {

    fun initialize(context: Context)

    suspend fun getInstalledAnimeExtensions(path: String?): List<Map<String, Any?>>

    suspend fun getInstalledMangaExtensions(): List<Map<String, Any?>>

    suspend fun getPopular(
        sourceId: String, isAnime: Boolean, page: Int
    ): Map<String, Any?>

    suspend fun getLatestUpdates(
        sourceId: String, isAnime: Boolean, page: Int
    ): Map<String, Any?>

    suspend fun search(
        sourceId: String, isAnime: Boolean, query: String, page: Int
    ): Map<String, Any?>

    suspend fun getDetail(
        sourceId: String, isAnime: Boolean, media: Map<String, Any?>
    ): Map<String, Any?>

    suspend fun getVideoList(
        sourceId: String, isAnime: Boolean, episode: Map<String, Any?>
    ): List<Map<String, Any?>>

    suspend fun getPageList(
        sourceId: String, isAnime: Boolean, episode: Map<String, Any?>
    ): List<Map<String, Any?>>

    suspend fun getPreference(
        sourceId: String, isAnime: Boolean
    ): List<Map<String, Any?>>

    suspend fun saveSourcePreference(
        sourceId: String, key: String, action: String, value: Any?
    ): Boolean
}