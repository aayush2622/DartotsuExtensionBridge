package com.lagradost.cloudstream3.plugins

import android.content.Context
import java.util.concurrent.ConcurrentHashMap

data class PluginData(
    val internalName: String,
    val url: String?,
    val isOnline: Boolean,
    val filePath: String,
    val version: Int,
)

/** The parts of upstream's PluginManager plugins call: mostly finding their own file. */
object PluginManager {
    const val ONLINE_PLUGINS_FOLDER = "Extensions"

    private val loaded = ConcurrentHashMap<String, PluginData>()

    fun register(data: PluginData) {
        loaded[data.filePath] = data
    }

    fun clear() = loaded.clear()

    fun getPluginsOnline(): Array<PluginData> = loaded.values.toTypedArray()

    fun getPluginsLocal(includeFailed: Boolean = false): Array<PluginData> = emptyArray()

    fun unloadPlugin(absolutePath: String) {
        loaded.remove(absolutePath)
    }

    suspend fun loadSinglePlugin(context: Context, apiName: String): Boolean = false
}
