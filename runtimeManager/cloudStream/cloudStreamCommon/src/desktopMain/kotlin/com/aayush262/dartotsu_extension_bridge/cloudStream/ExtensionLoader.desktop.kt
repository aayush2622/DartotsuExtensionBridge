package com.aayush262.dartotsu_extension_bridge.cloudStream

import com.lagradost.cloudstream3.plugins.PluginData
import com.lagradost.cloudstream3.plugins.PluginManager
import android.app.Application
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.aayush262.dartotsu_extension_bridge.ui.PluginResources
import com.aayush262.dartotsu_extension_bridge.util.PackageTools
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
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

    actual var plugins: MutableMap<String, LoadedPlugin> = ConcurrentHashMap()

    private val inFlight = ConcurrentHashMap<String, Future<*>>()
    private val failed = ConcurrentHashMap<String, Long>()

    // Converting a plugin (dex2jar + bytecode fixups) is the slow part and may take minutes for a
    // big one, so it runs off the caller's thread, two at a time. Registering the plugin's
    // providers touches shared, non-thread-safe lists, so that part takes [registryLock].
    private val workers: ExecutorService = Executors.newFixedThreadPool(2) { task ->
        Thread(task, "cloudstream-plugin-loader").apply { isDaemon = true }
    }
    private val registryLock = Any()
    private val scanLock = Any()

    actual fun pendingExtensions(): Int = inFlight.size

    actual fun preloadExtensions(path: String) {
        loadExtensions(File(path), 0)
    }

    actual fun refreshExtensions(path: String, waitMs: Long) {
        loadExtensions(File(path), waitMs)
    }

    actual fun loadExtensions(path: String) {
        loadExtensions(File(path), Long.MAX_VALUE)
    }

    private fun loadExtensions(dir: File, waitMs: Long) {
        if (!dir.exists() || !dir.isDirectory) return

        val files = dir.listFiles()
            ?.filter { it.isFile && (it.extension == "cs3" || it.extension == "jar") }
            ?: emptyList()

        val waiting = synchronized(scanLock) {
            val present = files.associateBy { it.absolutePath }

            // A plugin that was removed or replaced on disk is dropped; every other one stays
            // loaded, so providers never disappear while a refresh is running.
            for ((path, loaded) in plugins.entries.toList()) {
                val file = present[path]
                if (file == null || file.lastModified() != loaded.stamp) unloadPlugin(path)
            }
            failed.keys.removeAll { !present.containsKey(it) }

            for (file in files) {
                val path = file.absolutePath
                if (plugins.containsKey(path) || inFlight.containsKey(path)) continue
                if (failed[path] == file.lastModified()) continue
                inFlight[path] = workers.submit {
                    try {
                        if (!loadExtension(file)) failed[path] = file.lastModified()
                    } finally {
                        inFlight.remove(path)
                    }
                }
            }
            files.mapNotNull { inFlight[it.absolutePath] }
        }

        val deadline = if (waitMs == Long.MAX_VALUE) Long.MAX_VALUE else System.currentTimeMillis() + waitMs
        for (job in waiting) {
            val left = if (deadline == Long.MAX_VALUE) Long.MAX_VALUE else deadline - System.currentTimeMillis()
            if (left <= 0) break
            try {
                if (left == Long.MAX_VALUE) job.get() else job.get(left, TimeUnit.MILLISECONDS)
            } catch (_: TimeoutException) {
                break
            } catch (_: Exception) {
            }
        }

        val pending = inFlight.size
        Logger.log(
            "Loaded ${plugins.size} plugins" + if (pending > 0) ", $pending still loading" else ""
        )
    }

    private fun unloadPlugin(path: String) {
        synchronized(registryLock) {
            plugins.remove(path)?.let {
                try {
                    it.plugin.beforeUnload()
                } catch (_: Exception) {
                }
            }
            APIHolder.allProviders.removeAll { it.sourcePlugin == path }
            APIHolder.apis.removeAll { it.sourcePlugin == path }
            extractorApis.removeAll { it.sourcePlugin == path }
            PluginManager.unloadPlugin(path)
        }
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

                        PackageTools.markConverted(jarFile)
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

            val app: Application by KoinPlatformTools.defaultContext().get().inject()
            synchronized(registryLock) {
                plugins[file.absolutePath] = LoadedPlugin(
                    plugin = plugin,
                    manifest = manifest,
                    stamp = file.lastModified()
                )
                PluginManager.register(
                    PluginData(manifest.name, null, true, file.absolutePath, manifest.version)
                )
                try {
                    if (plugin is Plugin) {
                        plugin.resources = PluginResources(loader)
                        plugin.load(app.applicationContext)
                    } else {
                        plugin.load()
                    }
                } catch (e: Throwable) {
                    unloadPlugin(file.absolutePath)
                    throw e
                }
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
        synchronized(registryLock) {
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
        }
        failed.clear()

        Logger.log("Unloaded all plugins")
    }

}