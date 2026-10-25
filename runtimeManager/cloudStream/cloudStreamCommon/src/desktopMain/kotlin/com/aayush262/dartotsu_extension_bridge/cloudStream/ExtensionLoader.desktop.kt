package com.aayush262.dartotsu_extension_bridge.cloudStream

import com.lagradost.cloudstream3.plugins.PluginData
import com.lagradost.cloudstream3.plugins.PluginManager
import android.app.Application
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.aayush262.dartotsu_extension_bridge.ui.PluginResources
import com.aayush262.dartotsu_extension_bridge.util.ExtensionConvert
import com.aayush262.dartotsu_extension_bridge.util.PackageTools
import java.util.concurrent.ConcurrentHashMap
import com.lagradost.cloudstream3.APIHolder
import com.lagradost.cloudstream3.plugins.BasePlugin
import com.lagradost.cloudstream3.plugins.Plugin
import com.lagradost.cloudstream3.utils.AppUtils.parseJson
import com.lagradost.cloudstream3.utils.extractorApis
import org.koin.mp.KoinPlatformTools
import java.io.File
import kotlin.collections.set
import kotlin.getValue

actual object ExtensionLoader {


    // ConcurrentHashMap: loadExtension writes plugins[...] and the conversion
    // now runs a few files at a time.
    actual var plugins: MutableMap<String, LoadedPlugin> = ConcurrentHashMap()

    @Synchronized  // two concurrent getInstalled* polls raced APK->jar conversion
    actual fun loadExtensions(path: String) {

        val dir = File(path)

        if (!dir.exists() || !dir.isDirectory) return

        val pluginFiles = dir.listFiles()
            ?.filter { it.isFile && (it.extension == "cs3" || it.extension == "jar") }
            ?: emptyList()

        ExtensionConvert.parallel(pluginFiles, { it.name }) { file -> loadExtension(file) }

        Logger.log("Loaded ${plugins.size} plugins")

    }


    fun loadExtension(file: File): Boolean {
        if (!file.exists()) {
            Logger.log("Plugin file does not exist: ${file.absolutePath}")
            return false
        }

        val jarDir = File(file.parentFile, "jar")
        if (!jarDir.exists()) jarDir.mkdirs()

        val jarFile = File(
            jarDir,
            "${file.nameWithoutExtension}.jar"
        )

        try {
            when (file.extension.lowercase()) {
                "cs3" -> {
                    if (PackageTools.needsConversion(file, jarFile)) {
                        Logger.log("Building jar for ${file.name}")

                        // Same path as the previous build: a cached loader keeps the old
                        // jar's file handle open. On Windows that handle blocks both the
                        // dex2jar move below and extractAssetsFromApk from writing over
                        // it ("The process cannot access the file because it is being
                        // used by another process") — the loader has to go first, not
                        // after the jar is rebuilt.
                        PackageTools.invalidateClassLoader(jarFile.absolutePath)

                        PackageTools.dex2jar(
                            file.absolutePath,
                            jarFile.absolutePath
                        )

                        PackageTools.extractAssetsFromApk(
                            file.absolutePath,
                            jarFile.absolutePath
                        )
                    }
                }

                "jar" -> {
                    if (
                        !jarFile.exists() ||
                        file.lastModified() > jarFile.lastModified()
                    ) {
                        Logger.log("Copying jar ${file.name}")

                        PackageTools.invalidateClassLoader(jarFile.absolutePath)

                        file.copyTo(
                            target = jarFile,
                            overwrite = true
                        )
                    }
                }

                else -> {
                    error("Unsupported plugin format: ${file.extension}")
                }
            }

            val loader = PackageTools.getClassLoader(
                jarFile.absolutePath
            )

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

            plugins[file.absolutePath] = LoadedPlugin(
                plugin = plugin,
                manifest = manifest
            )
            PluginManager.register(
                PluginData(manifest.name, null, true, file.absolutePath, manifest.version)
            )
            val app: Application by KoinPlatformTools.defaultContext().get().inject()
            if (plugin is Plugin) {
                plugin.resources = PluginResources(loader)
                plugin.load(app.applicationContext)
            } else {
                plugin.load()
            }
            Logger.log(
                "Loaded plugin ${manifest.name} v${manifest.version}"
            )

            return true

        } catch (e: Throwable) {
            Logger.log(
                "Failed loading ${file.name}: ${e.message}\n${e.stackTraceToString()}"
            )
            // A loader cached by getClassLoader() before the failure (e.g. the
            // class loaded but failed verification) would otherwise sit there
            // holding the jar open — locking Windows out of both the next
            // rebuild attempt and the app's own cache cleanup.
            PackageTools.invalidateClassLoader(jarFile.absolutePath)
            return false
        }
    }


    actual fun releaseCachedJar(jarPath: String) {
        PackageTools.invalidateClassLoader(jarPath)
    }

    actual fun unloadExtensions() {
        APIHolder.allProviders.clear()
        APIHolder.apis.clear()

        plugins.values.forEach {
            try {
                it.plugin.beforeUnload()
            } catch (_: Exception) {
            }
        }
        extractorApis.clear()
        plugins.clear()
        PluginManager.clear()

        Logger.log("Unloaded all plugins")
    }

}