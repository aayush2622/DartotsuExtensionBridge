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
    var plugins: MutableMap<String, BasePlugin> = mutableMapOf()

    fun loadExtensions(path: String) {

        val dir = File(path)

        if (!dir.exists() || !dir.isDirectory) return

        val pluginFiles = dir.listFiles()
            ?.filter { it.isFile && (it.extension == "cs3" || it.extension == "jar") }
            ?: emptyList()


        pluginFiles.forEach { file ->
            try {
                loadPlugin(file)
            } catch (e: Throwable) {
                println("Failed to load ${file.name}: ${e.message}\n${e.stackTraceToString()}")
            }
        }

        println("Loaded ${plugins.size} plugins")

    }


/*
    fun getPluginsOnline(): Array<PluginData> {
        return DataStore.getPrefs()?.let {
            it.getString(PLUGINS_KEY, null)?.let { json ->
                parseJson<Array<PluginData>>(json)
            }
        } ?: emptyArray()
    }

    private fun setPluginsOnline(plugins: Array<PluginData>) {
        setKey(PLUGINS_KEY, plugins)
    }

    private fun updatePluginData(data: PluginData) {
        val plugins = getPluginsOnline().toMutableList()
        val index = plugins.indexOfFirst { it.internalName == data.internalName }
        if (index != -1) {
            plugins[index] = data
        } else {
            plugins.add(data)
        }
        setPluginsOnline(plugins.toTypedArray())
    }

    fun getPluginSanitizedFileName(url: String): String {
        return url.replace(Regex("""[^a-zA-Z0-9.\-]"""), "_")
    }

    fun getPluginPath(
        context: Context,
        internalName: String,
        repositoryUrl: String
    ): File {
        val folderName = getPluginSanitizedFileName(repositoryUrl)
        val fileName = getPluginSanitizedFileName(internalName)
        return File("${context.filesDir}/${ONLINE_PLUGINS_FOLDER}/${folderName}/$fileName.cs3")
    }*/



    fun loadPlugin(file: File): Boolean {
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
/*    fun loadPlugin(context: Context, file: File): Boolean {
        val pluginPath = file.absolutePath

        if (!file.exists()) {
             Logger.log( "Plugin file ${file.absolutePath} does not exist.")
            return false
        }
        val filePath = file.absolutePath

        val pluginData = getPluginsOnline().firstOrNull { it.filePath == filePath }
        if (pluginData?.isDisabled == true || pluginData?.isDownloaded == false) {
             Logger.log( "Plugin ${file.absolutePath} is disabled or not fully downloaded.")
            return false
        }

        try {
            Logger.log( "Loading plugin from ${file.absolutePath}")
            val loader = PathClassLoader(filePath, PluginManager::class.java.classLoader)

            val manifestUrl = loader.getResource("manifest.json")
            if (manifestUrl == null) {
                 Logger.log( "Plugin ${file.name} does not contain manifest.json")
                return false
            }

            val manifestText = manifestUrl.openStream().bufferedReader().use { it.readText() }
            val manifest = parseJson<BasePlugin.Manifest>(manifestText)

             Logger.log( "Parsed manifest: ${manifest.name} v${manifest.version}")

            @Suppress("UNCHECKED_CAST")
            val pluginClass = loader.loadClass(manifest.pluginClassName) as Class<out BasePlugin?>
            val pluginInstance: BasePlugin = pluginClass.getDeclaredConstructor().newInstance() as BasePlugin

            plugins[filePath] = pluginInstance
            pluginInstance.filename = filePath

            if (pluginInstance is Plugin) {
                pluginInstance.load(context)
            } else {
                pluginInstance.load() // For BasePlugin
            }

            if (pluginData == null) {
                // Was not tracked yet, store data
                updatePluginData(
                    PluginData(
                        internalName = manifest.name,
                        name = manifest.name,
                        tvTypes = manifest.tvTypes,
                        version = manifest.version,
                        url = "",
                        iconUrl = "",
                        filePath = filePath,
                        isDisabled = false,
                        isDownloaded = true
                    )
                )
            }

            return true

        } catch (e: Exception) {
             Logger.log( "Error loading plugin ${file.absolutePath}", e)
            return false
        }
    }*/


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