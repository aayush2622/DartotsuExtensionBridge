package com.aayush262.dartotsu_extension_bridge.cloudStream

import android.annotation.SuppressLint
import android.content.res.AssetManager
import android.content.res.Resources
import dalvik.system.PathClassLoader
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.lagradost.cloudstream3.APIHolder
import com.lagradost.cloudstream3.AcraApplication
import com.lagradost.cloudstream3.CloudStreamApp
import com.lagradost.cloudstream3.mapper
import com.lagradost.cloudstream3.plugins.BasePlugin
import com.lagradost.cloudstream3.plugins.Plugin
import com.lagradost.cloudstream3.utils.AppUtils.parseJson
import com.lagradost.cloudstream3.utils.extractorApis
import java.io.File
import java.io.IOException
import kotlin.jvm.java

@SuppressLint("StaticFieldLeak")
actual object ExtensionLoader {

    private val context: android.content.Context
        get() = CloudStreamApp.context
            ?: AcraApplication.context
            ?: error("Context is null")
    actual var plugins = mutableMapOf<String, LoadedPlugin>()
    actual fun loadExtensions(path: String) {
        val privateDir = File(context.filesDir, "cloudstream-plugins")
        val externalDir = File(path)

        privateDir.mkdirs()

        val externalFiles = externalDir.listFiles()
            ?.filter { it.isFile && (it.extension == "apk" || it.extension == "cs3") }
            ?: emptyList()

        val privateFiles = privateDir.listFiles()
            ?.associateBy { it.name }
            ?: emptyMap()

        externalFiles.forEach { src ->
            val dst = File(privateDir, src.name)

            val shouldCopy = !dst.exists() || dst.length() != src.length()

            if (shouldCopy) {
                val tmp = File(privateDir, "${src.name}.tmp")

                src.inputStream().use { input ->
                    tmp.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }

                if (!tmp.renameTo(dst)) {
                    tmp.delete()
                    throw IOException("Failed to finalize ${dst.name}")
                }

                dst.setReadOnly()
            }
        }

        privateFiles.forEach { (name, file) ->
            if (externalFiles.none { it.name == name }) {
                file.delete()
            }
        }

        plugins.keys.forEach { AndroidPreferenceRecorder.unregister(File(it).nameWithoutExtension) }
        plugins.clear()

        privateDir.listFiles()
            ?.filter { it.isFile && (it.extension == "apk" || it.extension == "cs3") }
            ?.forEach { file ->
                try {
                    loadPlugin(file)
                } catch (e: Throwable) {
                    Logger.log(
                        "Failed loading ${file.name}: ${e.stackTraceToString()}",
                    )
                }
            }

        Logger.log("Loaded ${plugins.size} plugins")
    }

    fun loadPlugin(
        file: File,
    ): Boolean {

        if (!file.exists()) {
            Logger.log("Plugin file does not exist: ${file.absolutePath}")
            return false
        }
        val parent = context.classLoader!!
        return try {
            val loader = PathClassLoader(
                file.absolutePath,
                parent
            )
            AndroidPreferenceRecorder.register(file.nameWithoutExtension, loader)

            val manifestText =
                loader.getResourceAsStream("manifest.json")
                    ?.bufferedReader()
                    ?.use { it.readText() }
                    ?: error("manifest.json not found")

            val manifest = parseJson<BasePlugin.Manifest>(manifestText)

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
            if (plugin is Plugin && manifest.requiresResources) {
                plugin.resources = pluginResources(file)
            }

            plugins[file.absolutePath] = LoadedPlugin(
                plugin = plugin,
                manifest = manifest
            )
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
            AndroidPreferenceRecorder.unregister(file.nameWithoutExtension)
            Logger.log(
                "Failed loading ${file.name}: ${e.message}\n${e.stackTraceToString()}"
            )
            false
        }
    }

    private fun pluginResources(file: File): Resources {
        val assets = AssetManager::class.java.getDeclaredConstructor().newInstance()
        AssetManager::class.java.getMethod("addAssetPath", String::class.java)
            .invoke(assets, file.absolutePath)
        val base = context.resources
        @Suppress("DEPRECATION")
        return Resources(assets, base.displayMetrics, base.configuration)
    }

    actual fun unloadExtensions() {
        APIHolder.allProviders.clear()
        APIHolder.apis.clear()

        plugins.forEach { (path, loaded) ->
            try {
                loaded.plugin.beforeUnload()
            } catch (_: Exception) {
            }
            AndroidPreferenceRecorder.unregister(File(path).nameWithoutExtension)
        }
        extractorApis.clear()
        plugins.clear()

        Logger.log("Unloaded all plugins")
    }
}