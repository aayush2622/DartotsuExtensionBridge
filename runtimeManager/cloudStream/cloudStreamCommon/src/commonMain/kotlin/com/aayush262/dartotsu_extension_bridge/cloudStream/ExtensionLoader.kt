package com.aayush262.dartotsu_extension_bridge.cloudStream

import com.lagradost.cloudstream3.plugins.BasePlugin

expect object ExtensionLoader{
    var plugins : MutableMap<String, LoadedPlugin>
    fun loadExtensions(path: String)
    fun unloadExtensions()
    fun releaseCachedJar(jarPath: String)

    /** Plugins still being prepared in the background (desktop converts and loads them off-thread). */
    fun pendingExtensions(): Int

    /**
     * Brings the loaded plugins in line with [path], waiting at most [waitMs] for the ones that
     * need preparing. Plugins already loaded stay usable the whole time.
     */
    fun refreshExtensions(path: String, waitMs: Long)

    /** Starts preparing the plugins in [path] without waiting for them. */
    fun preloadExtensions(path: String)
}

data class LoadedPlugin(
    val plugin: BasePlugin,
    val manifest: BasePlugin.Manifest,
    val stamp: Long = 0L,
)