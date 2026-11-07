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
import java.util.concurrent.atomic.AtomicLong
import com.lagradost.cloudstream3.APIHolder
import com.lagradost.cloudstream3.plugins.BasePlugin
import com.lagradost.cloudstream3.plugins.Plugin
import com.lagradost.cloudstream3.utils.AppUtils.parseJson
import com.lagradost.cloudstream3.mapper
import com.lagradost.cloudstream3.utils.Coroutines
import com.lagradost.cloudstream3.utils.extractorApis
import org.koin.mp.KoinPlatformTools
import java.io.File
import kotlin.collections.set
import kotlin.getValue

actual object ExtensionLoader {

    actual var plugins: MutableMap<String, LoadedPlugin> = ConcurrentHashMap()

    private val inFlight = ConcurrentHashMap<String, Future<*>>()

    private class Entry(val path: String, val name: String) {
        var version = 0L
        var state = "queued"
        var progress = 0.0
        var error: String? = null
        var sources: List<Map<String, Any?>>? = null
    }

    private val entries = HashMap<String, Entry>()
    private val changes = AtomicLong()
    private val failed = ConcurrentHashMap<String, Long>()

    // Converting a plugin (dex2jar + bytecode fixups) is the slow part and may take minutes for a
    // big one, so it runs off the caller's thread, a few at a time. Registering the plugin's
    // providers touches shared, non-thread-safe lists, so that part takes [registryLock].
    private val workers: ExecutorService = Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors().div(2).coerceIn(2, 8)) { task ->
        Thread(task, "cloudstream-plugin-loader").apply { isDaemon = true }
    }
    private val registryLock = Any()
    private val scanLock = Any()

    actual fun pendingExtensions(): Int = inFlight.size

    actual fun changeVersion(): Long = changes.get()

    actual fun changesSince(since: Long): String = synchronized(entries) {
        mapper.writeValueAsString(
            mapOf(
                "version" to changes.get(),
                "entries" to entries.values.filter { it.version > since }.map {
                    mapOf(
                        "path" to it.path,
                        "name" to it.name,
                        "state" to it.state,
                        "progress" to it.progress,
                        "error" to it.error,
                        "sources" to it.sources,
                    )
                },
            )
        )
    }

    private fun update(path: String, block: Entry.() -> Unit) {
        synchronized(entries) {
            val entry = entries.getOrPut(path) { Entry(path, File(path).nameWithoutExtension) }
            entry.block()
            entry.version = changes.incrementAndGet()
        }
    }

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
            val gone = synchronized(entries) {
                entries.values.filter { it.state != "removed" && !present.containsKey(it.path) }.map { it.path }
            }
            gone.forEach { update(it) { state = "removed"; sources = null; error = null } }

            for (file in files) {
                val path = file.absolutePath
                if (plugins.containsKey(path) || inFlight.containsKey(path)) continue
                if (failed[path] == file.lastModified()) continue
                update(path) { state = "queued"; progress = 0.0; error = null; sources = null }
                inFlight[path] = workers.submit {
                    try {
                        if (loadExtension(file)) {
                            update(path) { state = "ready"; progress = 1.0; sources = CloudStreamSources.of(path) }
                        } else {
                            failed[path] = file.lastModified()
                            update(path) { state = "failed"; error = error ?: "Could not load the plugin" }
                        }
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
            update(path) { state = "removed"; sources = null; error = null }
            APIHolder.allProviders.removeAll { it.sourcePlugin == path }
            APIHolder.apis = APIHolder.apis.filter { it.sourcePlugin != path }
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
                        update(file.absolutePath) { state = "converting"; progress = 0.0 }

                        // Same path as the previous build: a cached loader keeps the old
                        // jar's file handle open. On Windows that handle blocks both the
                        // dex2jar move below and extractAssetsFromApk from writing over
                        // it ("The process cannot access the file because it is being
                        // used by another process") — the loader has to go first, not
                        // after the jar is rebuilt.
                        PackageTools.invalidateClassLoader(jarFile.absolutePath)

                        var reported = 0.0
                        PackageTools.cloudStreamToJar(
                            file.absolutePath,
                            jarFile.absolutePath
                        ) { value ->
                            if (value - reported >= 0.01) {
                                reported = value
                                update(file.absolutePath) { progress = value }
                            }
                        }

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

            update(file.absolutePath) { state = "loading"; progress = 1.0 }

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
                    PluginData(manifest.name ?: file.nameWithoutExtension, null, true, file.absolutePath, manifest.version ?: 0)
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
            update(file.absolutePath) { error = e.message ?: e.javaClass.simpleName }
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
            APIHolder.apis = Coroutines.atomicListOf()

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
        val paths = synchronized(entries) { entries.keys.toList() }
        paths.forEach { update(it) { state = "removed"; sources = null; error = null } }

        Logger.log("Unloaded all plugins")
    }

}