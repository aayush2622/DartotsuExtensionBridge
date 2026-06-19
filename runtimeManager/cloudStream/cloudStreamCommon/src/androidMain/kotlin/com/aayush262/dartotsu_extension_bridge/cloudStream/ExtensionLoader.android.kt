package com.aayush262.dartotsu_extension_bridge.cloudStream

import android.content.Context
import dalvik.system.PathClassLoader
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.lagradost.cloudstream3.APIHolder
import com.lagradost.cloudstream3.CloudStreamApp
import com.lagradost.cloudstream3.plugins.BasePlugin
import com.lagradost.cloudstream3.plugins.Plugin
import com.lagradost.cloudstream3.utils.AppUtils.parseJson
import java.io.File

actual object ExtensionLoader {
    private val plugins = mutableMapOf<String, BasePlugin>()

    fun loadExtensions(path: String) {
        val dir = File(path)

        if (!dir.exists() || !dir.isDirectory) return

        dir.listFiles()
            ?.filter { it.isFile && (it.extension == "cs3" || it.extension == "apk") }
            ?.forEach { file ->
                try {
                    loadPlugin(file)
                } catch (e: Throwable) {
                    Logger.log(
                        "Failed to load ${file.name}: ${e.message}\n${e.stackTraceToString()}"
                    )
                }
            }

        Logger.log("Loaded ${plugins.size} plugins")
    }

    fun loadPlugin(
        file: File,
    ): Boolean {
        val context = CloudStreamApp.context ?: error("Context is null")
        if (!file.exists()) {
            Logger.log("Plugin file does not exist: ${file.absolutePath}")
            return false
        }

        return try {
            val loader = PathClassLoader(
                file.absolutePath,
                javaClass.classLoader
            )

            val manifestText =
                loader.getResourceAsStream("manifest.json")
                    ?.bufferedReader()
                    ?.use { it.readText() }
                    ?: error("manifest.json not found")

            val manifest =
                parseJson<BasePlugin.Manifest>(manifestText)

            @Suppress("UNCHECKED_CAST")
            val pluginClass =
                loader.loadClass(
                    manifest.pluginClassName
                ) as Class<out BasePlugin>

            val plugin =
                pluginClass
                    .getDeclaredConstructor()
                    .newInstance()

            plugin.filename = file.absolutePath
            plugins[file.absolutePath] = plugin

            if (plugin is Plugin) {
                plugin.load(context.applicationContext)
            } else {
                plugin.load()
            }

            Logger.log(
                "Loaded plugin ${manifest.name} v${manifest.version}"
            )

            true
        } catch (e: Throwable) {
            Logger.log(
                "Failed loading ${file.name}: ${e.message}\n${e.stackTraceToString()}"
            )
            false
        }
    }

    fun unloadExtensions() {
        APIHolder.allProviders.clear()
        APIHolder.apis.clear()

        plugins.values.forEach {
            try {
                it.beforeUnload()
            } catch (_: Exception) {
            }
        }

        plugins.clear()

        Logger.log("Unloaded all plugins")
    }
}