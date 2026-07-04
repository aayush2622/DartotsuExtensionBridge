package com.aayush262.dartotsu_extension_bridge.cloudStream

import android.app.Application
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.aayush262.dartotsu_extension_bridge.util.PackageTools
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


    actual var plugins = mutableMapOf<String, LoadedPlugin>()

    actual fun loadExtensions(path: String) {

        val dir = File(path)

        if (!dir.exists() || !dir.isDirectory) return

        val pluginFiles = dir.listFiles()
            ?.filter { it.isFile && (it.extension == "cs3" || it.extension == "jar") }
            ?: emptyList()


        pluginFiles.forEach { file ->
            try {
                loadExtension(file)
            } catch (e: Throwable) {
                Logger.log("Failed to load ${file.name}: ${e.message}\n${e.stackTraceToString()}")
            }
        }

        Logger.log("Loaded ${plugins.size} plugins")

    }


    fun loadExtension(file: File): Boolean {
        if (!file.exists()) {
            Logger.log("Plugin file does not exist: ${file.absolutePath}")
            return false
        }

        try {
            val jarDir = File(file.parentFile, "jar")
            if (!jarDir.exists()) jarDir.mkdirs()

            val jarFile = File(
                jarDir,
                "${file.nameWithoutExtension}.jar"
            )

            when (file.extension.lowercase()) {
                "cs3" -> {
                    val shouldBuildJar = when {
                        !jarFile.exists() -> true
                        file.lastModified() > jarFile.lastModified() -> true
                        else -> false
                    }

                    if (shouldBuildJar) {
                        Logger.log("Building jar for ${file.name}")

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
            val app: Application by KoinPlatformTools.defaultContext().get().inject()
            if (plugin is Plugin) {
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
            return false
        }
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

        plugins.clear()

        Logger.log("Unloaded all plugins")
    }

}