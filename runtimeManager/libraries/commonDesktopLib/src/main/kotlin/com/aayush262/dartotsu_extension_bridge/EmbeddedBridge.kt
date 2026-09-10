package com.aayush262.dartotsu_extension_bridge

import com.aayush262.dartotsu_extension_bridge.util.ChildFirstURLClassLoader
import com.google.gson.Gson
import com.google.gson.JsonObject
import kotlinx.coroutines.runBlocking
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * In-process entry point for the iOS embedded OpenJDK Zero VM.
 *
 * On desktop each backend fat JAR is its own `java -jar` process whose
 * `Main.main` runs [Server.run] over stdio. iOS cannot spawn a process, so a
 * single VM is created with only this class' JAR on the classpath (see
 * `ios/Classes/EmbeddedJvm.mm`) and every backend JAR is attached here in its
 * own [ChildFirstURLClassLoader]. The native layer then calls [load] / [call]
 * / [unload] over JNI; [call] speaks the same request/response shape the
 * sidecar does.
 *
 * All methods are `@JvmStatic` so the native `GetStaticMethodID` lookups
 * resolve.
 */
object EmbeddedBridge {
    private const val MAIN_CLASS = "com.aayush262.dartotsu_extension_bridge.Main"

    private class Loaded(
        val loader: ChildFirstURLClassLoader,
        val api: ExtensionApi,
    )

    private val loaded = ConcurrentHashMap<String, Loaded>()
    private val gson = Gson()

    @JvmStatic
    fun load(jarPath: String) {
        loaded.computeIfAbsent(jarPath) {
            val file = File(jarPath)
            require(file.isFile) { "Backend JAR not found: $jarPath" }

            val loader = ChildFirstURLClassLoader(
                arrayOf(file.toURI().toURL()),
                EmbeddedBridge::class.java.classLoader,
            )
            val mainClass = Class.forName(MAIN_CLASS, true, loader)
            val api = mainClass.getMethod("api").invoke(null) as ExtensionApi
            Loaded(loader, api)
        }
    }

    @JvmStatic
    fun call(jarPath: String, requestJson: String): String {
        val entry = loaded[jarPath]
            ?: return failure(IllegalStateException("JAR not loaded: $jarPath"))

        val req = gson.fromJson(requestJson, JsonObject::class.java)
        val method = req["method"].asString
        val params = req["args"]?.asJsonObject ?: JsonObject()

        val previousLoader = Thread.currentThread().contextClassLoader
        return try {
            Thread.currentThread().contextClassLoader = entry.loader
            val data = runBlocking { Server.handle(entry.api, method, params) }
            gson.toJson(mapOf("success" to true, "data" to data))
        } catch (e: Throwable) {
            failure(e)
        } finally {
            Thread.currentThread().contextClassLoader = previousLoader
        }
    }

    @JvmStatic
    fun unload(jarPath: String) {
        loaded.remove(jarPath)?.loader?.let { runCatching { it.close() } }
    }

    /** Lifecycle hooks from the app; nothing to trim yet. */
    @JvmStatic
    fun pause() {
    }

    @JvmStatic
    fun resume() {
    }

    private fun failure(e: Throwable): String = gson.toJson(
        mapOf(
            "success" to false,
            "error" to (e.message ?: e.javaClass.simpleName),
            "trace" to e.stackTraceToString(),
        ),
    )
}
