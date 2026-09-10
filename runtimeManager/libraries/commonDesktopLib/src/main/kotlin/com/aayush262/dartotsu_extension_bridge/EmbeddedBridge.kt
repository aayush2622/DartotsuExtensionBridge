package com.aayush262.dartotsu_extension_bridge

import java.io.File
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method
import java.net.URLClassLoader
import java.util.concurrent.ConcurrentHashMap

/**
 * In-process entry point for the iOS embedded OpenJDK Zero VM.
 *
 * On desktop each backend fat JAR is its own `java -jar` process whose
 * `Main.main` runs [Server.run] over stdio. iOS can't spawn a process, so a
 * single VM is created with only this class' slim JAR on `-Djava.class.path`
 * (see `ios/Classes/EmbeddedJvm.mm`); the native layer then calls
 * [load] / [call] / [unload] / [pause] / [resume] / [isRunning] over JNI.
 *
 * ## Isolation
 *
 * Each backend JAR is a self-contained shadow JAR (its own kotlin-stdlib,
 * coroutines, gson, koin, okhttp, AndroidCompat, tachiyomi framework, and a
 * full copy of `com.aayush262.dartotsu_extension_bridge.**`). It is loaded in
 * a [URLClassLoader] whose parent is the **platform** class loader — JDK
 * classes only, *not* this shim's loader. Consequences:
 *
 *  * every backend gets its own statics (Koin `GlobalContext`, Injekt, the
 *    `Looper`, metadata caches) — no cross-backend collision, exactly like the
 *    separate desktop processes;
 *  * nothing crosses the shim↔backend boundary except `java.lang.String`, so
 *    there is no shared-coroutine-runtime / shared-gson hazard;
 *  * the whole request runs inside the backend's loader via `Main.handle` —
 *    `runBlocking`, `Server`, `ExtensionApi` are all the backend's own.
 *
 * All methods are `@JvmStatic` so the native `GetStaticMethodID` lookups
 * resolve.
 */
object EmbeddedBridge {
    private const val MAIN_CLASS = "com.aayush262.dartotsu_extension_bridge.Main"

    private class Loaded(
        val loader: URLClassLoader,
        /** `Main.handle(String): String` — one request in, envelope JSON out. */
        val handle: Method,
    )

    private val loaded = ConcurrentHashMap<String, Loaded>()

    @JvmStatic
    fun load(jarPath: String) {
        loaded.computeIfAbsent(jarPath) {
            val file = File(jarPath)
            require(file.isFile) { "Backend JAR not found: $jarPath" }

            val loader = URLClassLoader(
                arrayOf(file.toURI().toURL()),
                ClassLoader.getPlatformClassLoader(),
            )
            val mainClass = Class.forName(MAIN_CLASS, true, loader)
            val handle = mainClass.getMethod("handle", String::class.java)
            Loaded(loader, handle)
        }
    }

    @JvmStatic
    fun call(jarPath: String, requestJson: String): String {
        val entry = loaded[jarPath]
            ?: return errorEnvelope("JAR not loaded: $jarPath", null)

        val previous = Thread.currentThread().contextClassLoader
        return try {
            Thread.currentThread().contextClassLoader = entry.loader
            entry.handle.invoke(null, requestJson) as String
        } catch (e: Throwable) {
            val cause = (e as? InvocationTargetException)?.targetException ?: e
            errorEnvelope(
                cause.message ?: cause.javaClass.simpleName,
                cause.stackTraceToString(),
            )
        } finally {
            Thread.currentThread().contextClassLoader = previous
        }
    }

    @JvmStatic
    fun unload(jarPath: String) {
        loaded.remove(jarPath)?.loader?.let { runCatching { it.close() } }
    }

    /**
     * App-lifecycle hooks. Like M-Extension-Server's `EmbeddedBridge.pause`,
     * these deliberately keep every loaded backend + its source instances warm
     * across an iOS background/resume cycle so a resume does not repeat APK
     * conversion and source initialization. The JVM shutdown hook still does
     * full cleanup when the process exits.
     */
    @JvmStatic
    fun pause() {
    }

    @JvmStatic
    fun resume() {
    }

    /** Parity with M-Extension-Server; true once any backend JAR is loaded. */
    @JvmStatic
    fun isRunning(): Boolean = loaded.isNotEmpty()

    // Hand-rolled so the shim JAR needs no JSON library on its classpath.
    private fun errorEnvelope(message: String, trace: String?): String {
        val sb = StringBuilder("""{"success":false,"error":""")
        appendEscaped(sb, message)
        sb.append('"')
        if (trace != null) {
            sb.append(""","trace":"""")
            appendEscaped(sb, trace)
            sb.append('"')
        }
        return sb.append('}').toString()
    }

    private fun appendEscaped(sb: StringBuilder, s: String) {
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> if (c < ' ') sb.append("\\u%04x".format(c.code)) else sb.append(c)
            }
        }
    }
}
