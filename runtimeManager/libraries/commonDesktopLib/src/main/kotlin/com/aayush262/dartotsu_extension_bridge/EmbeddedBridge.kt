package com.aayush262.dartotsu_extension_bridge

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.OutputStream
import java.io.PrintStream
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
 * A backend is a thin plugin JAR plus the shared `desktopCore` JAR (its
 * kotlin-stdlib, coroutines, gson, koin, okhttp, AndroidCompat, tachiyomi
 * framework and `com.aayush262.dartotsu_extension_bridge.**`). The caller
 * passes both as one class path string (`core.jar:plugin.jar`, split on
 * [File.pathSeparator]; a lone self-contained JAR works too). They are loaded
 * in one [URLClassLoader] per backend whose parent is the **platform** class
 * loader — JDK classes only, *not* this shim's loader, so the core's classes
 * are loaded again for every backend. Consequences:
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

    /** Registered by the native host; stream 1 = stdout, 2 = stderr. */
    @JvmStatic
    external fun nativeLog(stream: Int, line: String)

    /**
     * Routes System.out/err (shared by every backend loader, since
     * java.lang.System is a boot class) and uncaught exceptions to the host
     * log. Called by the native host once [nativeLog] is registered.
     */
    @JvmStatic
    fun installLogCapture() {
        System.setOut(PrintStream(LineSink(1), true, Charsets.UTF_8))
        System.setErr(PrintStream(LineSink(2), true, Charsets.UTF_8))
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            nativeLog(2, "Uncaught exception in thread \"${thread.name}\": ${error.stackTraceToString()}")
        }
        nativeLog(1, "Java log capture installed (java ${System.getProperty("java.version")}, " +
            "${System.getProperty("java.vm.name")} ${System.getProperty("java.vm.info")}, " +
            "max heap ${Runtime.getRuntime().maxMemory() / (1024 * 1024)} MB)")
    }

    private class LineSink(private val stream: Int) : OutputStream() {
        private val buffer = ByteArrayOutputStream()

        @Synchronized
        override fun write(b: Int) {
            if (b == '\n'.code) emit() else buffer.write(b)
        }

        @Synchronized
        override fun write(b: ByteArray, off: Int, len: Int) {
            for (i in off until off + len) write(b[i].toInt())
        }

        private fun emit() {
            val line = buffer.toString(Charsets.UTF_8).trimEnd('\r')
            buffer.reset()
            nativeLog(stream, line)
        }
    }

    @JvmStatic
    fun load(jarPath: String) {
        loaded.computeIfAbsent(jarPath) {
            val started = System.nanoTime()
            try {
                val files = jarPath.split(File.pathSeparatorChar)
                    .filter { it.isNotEmpty() }
                    .map(::File)
                require(files.isNotEmpty()) { "No backend JAR given" }
                files.forEach { require(it.isFile) { "Backend JAR not found: ${it.path}" } }

                val loader = URLClassLoader(
                    files.map { it.toURI().toURL() }.toTypedArray(),
                    ClassLoader.getPlatformClassLoader(),
                )
                val mainClass = Class.forName(MAIN_CLASS, true, loader)
                val handle = mainClass.getMethod("handle", String::class.java)
                System.out.println(
                    "Loaded ${files.last().name} (${files.sumOf { it.length() } / 1024} KB in ${files.size} JAR(s)) in ${(System.nanoTime() - started) / 1_000_000} ms",
                )
                Loaded(loader, handle)
            } catch (e: Throwable) {
                System.err.println("Loading $jarPath failed: ${e.stackTraceToString()}")
                throw e
            }
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
            System.err.println("Call failed: ${cause.stackTraceToString()}")
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
        System.out.println("Unloaded $jarPath")
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
