package com.aayush262.dartotsu_extension_bridge.cloudStream

import com.lagradost.cloudstream3.plugins.BasePlugin

expect object ExtensionLoader{
    var plugins : MutableMap<String, LoadedPlugin>
    fun loadExtensions(path: String)
    fun unloadExtensions()
    fun releaseCachedJar(jarPath: String)
}

data class LoadedPlugin(
    val plugin: BasePlugin,
    val manifest: BasePlugin.Manifest
)