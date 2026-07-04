package com.aayush262.dartotsu_extension_bridge.ireader

import ireader.core.source.CatalogSource

expect object ExtensionLoader{
    val plugins:MutableMap<Long, CatalogSource>
    fun loadExtensions(path: String): List<LoadedExtension>
}

data class LoadedExtension(
    val source: CatalogSource,
    val packageName: String,
    val versionCode: Long,
    val versionName: String,
    val baseUrl: String,
    val icon: String,
    val description: String,
    val apkPath: String,
)