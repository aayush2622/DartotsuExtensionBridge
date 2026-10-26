package xyz.nulldev.androidcompat.webkit

import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.jetbrains.cef.JCefAppConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import org.cef.CefApp
import org.cef.CefClient
import org.cef.SystemBootstrap
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.PosixFilePermission
import java.time.Duration
import kotlin.io.path.Path
import kotlin.io.path.absolutePathString
import kotlin.io.path.createDirectories
import kotlin.io.path.div
import kotlin.io.path.exists
import kotlin.io.path.isDirectory
import kotlin.io.path.listDirectoryEntries
import kotlin.io.path.readText
import kotlin.io.path.writeText

object CefHelper {
    val cefApp = MutableStateFlow<Result<CefApp?>>(Result.success(null))
    private val initMutex = Mutex()
    private var initStarted = false

    // The JetBrains Runtime build whose bundled native CEF matches the JCEF API version
    // `commonDesktop-lib.toml`'s "jcef" dependency is compiled against. Bump both together.
    private const val JBR_VERSION = "25.0.4"
    private const val JBR_BUILD = "b508.27"
    private const val VERSION_MARKER = ".dartotsu-jcef-version"

    suspend fun createClient(): CefClient {
        ensureInitialized()
        val app = waitForInit().first()
        val client = app.createClient()
        JsHandler(client) // This adds itself to a global map
        return client
    }

    /**
     * Bootstraps [CefApp] on first use and publishes the result to [cefApp]. Nothing did this
     * before - [cefApp] sat at its placeholder `Result.success(null)` forever, so every caller of
     * [createClient] (any Cloudflare-bypass/webview-backed source) hung indefinitely until its own
     * external timeout gave up, never actually loading a page.
     */
    private suspend fun ensureInitialized() {
        initMutex.withLock {
            if (initStarted) return
            initStarted = true

            withContext(Dispatchers.IO) {
                try {
                    if (isEmbeddedIos()) {
                        throw UnsupportedOperationException(
                            "WebView is not available on iOS: Chromium (JCEF) cannot run inside an iOS app",
                        )
                    }
                    val cefDir = installDir()
                    // Each backend (aniyomi/cloudStream/ireader/kotatsu/tsundoku) runs as its own
                    // JVM process, so [initMutex] alone doesn't stop two of them from racing to
                    // download+extract into the same shared cefDir at once - a real lock file
                    // serializes across processes too. Re-check validity after acquiring it: the
                    // other process may have just finished.
                    java.nio.channels.FileChannel
                        .open(
                            cefDir.parent!! / "kcef.lock",
                            StandardOpenOption.CREATE,
                            StandardOpenOption.WRITE,
                        ).use { channel ->
                            channel.lock().use {
                                if (!isInstallationValid(cefDir)) {
                                    downloadAndExtract(cefDir)
                                }
                            }
                        }

                    val app =
                        CefApp.getInstanceIfAny() ?: run {
                            val config =
                                JCefAppConfig.getInstance(cefDir.toString(), false).apply {
                                    appArgsAsList.addAll(
                                        listOf(
                                            "--disable-gpu",
                                            // Nothing ever presents a window for this browser.
                                            "--off-screen-rendering-enabled",
                                            "--disable-dev-shm-usage",
                                        ),
                                    )
                                    cefSettings.windowless_rendering_enabled = true
                                    cefSettings.cache_path =
                                        (cefDir / "cache").also { it.createDirectories() }.absolutePathString()
                                }

                            // Mirrors JCefAppConfig's own native bootstrap order - cef/chrome_elf/
                            // libcef must be loaded before jcef links against them.
                            when {
                                isLinux() -> config.loader.loadLibrary("cef")
                                isWindows() -> {
                                    config.loader.loadLibrary("chrome_elf")
                                    config.loader.loadLibrary("libcef")
                                }
                                else -> {}
                            }
                            config.loader.loadLibrary("jcef")

                            CefApp.setIsRemoteEnabled(config.isRemoteEnabled)
                            SystemBootstrap.setLoader(config.loader)
                            CefApp.startup(config.appArgs)

                            CefApp.getInstance(config.appArgs, config.cefSettings, config.serverExe)
                        }

                    cefApp.value = Result.success(app)
                    Logger.log("CEF app created", LogLevel.DEBUG)
                } catch (e: Throwable) {
                    Logger.log("Failed to set up CEF: ${e.stackTraceToString()}", LogLevel.ERROR)
                    cefApp.value = Result.failure(e)
                }
            }
        }
    }

    fun waitForInit() =
        callbackFlow {
            val app = cefApp.first { it.isFailure || it.getOrThrow() != null }.getOrThrow()!!
            app.onInitialization {
                Logger.log("CEF: Initialization state $it", LogLevel.DEBUG)
                when (it) {
                    CefApp.CefAppState.INITIALIZED -> {
                        trySend(app)
                        close()
                    }

                    CefApp.CefAppState.SHUTTING_DOWN, CefApp.CefAppState.TERMINATED -> {
                        close(CefException("Shutting down"))
                    }

                    else -> {}
                }
            }
            awaitClose {}
        }

    private fun installDir(): java.nio.file.Path =
        (Path(System.getProperty("user.home")) / ".dartotsu" / "kcef").also { it.createDirectories() }

    private fun isInstallationValid(cefDir: java.nio.file.Path): Boolean {
        val marker = cefDir / VERSION_MARKER
        if (!marker.exists() || !(cefDir / "lib").exists()) return false
        return runCatching { marker.readText() }.getOrNull() == "$JBR_VERSION-$JBR_BUILD"
    }

    private fun jbrOsArch(): Pair<String, String> {
        val osName = System.getProperty("os.name").lowercase()
        val archName = System.getProperty("os.arch").lowercase()

        val os =
            when {
                osName.contains("win") -> "windows"
                osName.contains("mac") -> "osx"
                else -> "linux"
            }
        val arch = if (archName.contains("aarch64") || archName.contains("arm")) "aarch64" else "x64"

        return os to arch
    }

    // Set by the iOS embedded VM's launch options (EmbeddedJvm.mm).
    private fun isEmbeddedIos() = System.getProperty("dartotsu.runtime") == "ios"

    private fun isLinux() = System.getProperty("os.name").lowercase().contains("linux")

    private fun isWindows() = System.getProperty("os.name").lowercase().contains("win")

    /**
     * `org.jetbrains.intellij.deps.jcef:jcef` is API-only - it ships no native libraries, because
     * it's meant to run inside a JetBrains Runtime (JBR) that already bundles them. Our bundled
     * JVM is a plain Temurin build, so the matching JBR's native `lib/` (built against the exact
     * same JCEF API version as that dependency) is downloaded separately, once, and cached under
     * [installDir] - the rest of that JBR's own JDK is discarded, we only need its native libs.
     */
    private fun downloadAndExtract(cefDir: java.nio.file.Path) {
        Logger.log("Downloading CEF runtime (JetBrains Runtime $JBR_VERSION-$JBR_BUILD)...", LogLevel.INFO)

        if (cefDir.exists()) cefDir.toFile().deleteRecursively()
        cefDir.createDirectories()

        val (os, arch) = jbrOsArch()
        val assetName = "jbr_jcef-$JBR_VERSION-$os-$arch-$JBR_BUILD.tar.gz"
        val url = "https://cache-redirector.jetbrains.com/intellij-jbr/$assetName"

        val client =
            OkHttpClient.Builder()
                .followRedirects(true)
                .connectTimeout(Duration.ofSeconds(30))
                .readTimeout(Duration.ofMinutes(10))
                .build()

        val tempArchive = Files.createTempFile("dartotsu-jcef-runtime", ".tar.gz")
        try {
            client.newCall(Request.Builder().url(url).build()).execute().use { response ->
                if (!response.isSuccessful) {
                    throw IOException("Failed to download CEF runtime ($url): HTTP ${response.code}")
                }
                response.body.byteStream().use { input ->
                    Files.newOutputStream(tempArchive, StandardOpenOption.TRUNCATE_EXISTING).use { out ->
                        input.copyTo(out)
                    }
                }
            }

            val staging = cefDir.parent ?: error("CEF install dir has no parent")
            staging.createDirectories()
            val extractTemp = Files.createTempDirectory(staging, "dartotsu-jcef-extract")
            try {
                extractTarGz(tempArchive, extractTemp)
                flattenInto(extractTemp, cefDir, os)
            } finally {
                extractTemp.toFile().deleteRecursively()
            }

            (cefDir / VERSION_MARKER).writeText("$JBR_VERSION-$JBR_BUILD")
            Logger.log("CEF runtime installed at $cefDir", LogLevel.INFO)
        } finally {
            Files.deleteIfExists(tempArchive)
        }
    }

    private fun extractTarGz(
        archive: java.nio.file.Path,
        destDir: java.nio.file.Path,
    ) {
        destDir.createDirectories()

        Files.newInputStream(archive).use { fileIn ->
            GzipCompressorInputStream(fileIn).use { gzipIn ->
                TarArchiveInputStream(gzipIn).use { tarIn ->
                    var entry = tarIn.nextEntry
                    while (entry != null) {
                        val target = destDir.resolve(entry.name).normalize()
                        if (!target.startsWith(destDir)) {
                            throw IOException("CEF archive entry escapes install dir: ${entry.name}")
                        }

                        when {
                            entry.isDirectory -> target.createDirectories()
                            entry.isSymbolicLink -> {
                                target.parent?.createDirectories()
                                Files.deleteIfExists(target)
                                Files.createSymbolicLink(target, Path(entry.linkName))
                            }
                            else -> {
                                target.parent?.createDirectories()
                                Files.newOutputStream(
                                    target,
                                    StandardOpenOption.CREATE,
                                    StandardOpenOption.TRUNCATE_EXISTING,
                                ).use { out -> tarIn.copyTo(out) }

                                runCatching {
                                    Files.setPosixFilePermissions(
                                        target,
                                        Files.getPosixFilePermissions(target) +
                                            setOf(
                                                PosixFilePermission.OWNER_EXECUTE,
                                                PosixFilePermission.GROUP_EXECUTE,
                                                PosixFilePermission.OTHERS_EXECUTE,
                                            ),
                                    )
                                }
                            }
                        }

                        entry = tarIn.nextEntry
                    }
                }
            }
        }
    }

    /**
     * Keeps only the native `lib/` (and, on macOS, `Frameworks/`) from the downloaded JBR - the
     * rest of that JDK is discarded since our own bundled JVM already provides the Java runtime.
     */
    private fun flattenInto(
        extractedRoot: java.nio.file.Path,
        cefDir: java.nio.file.Path,
        os: String,
    ) {
        val topLevel =
            extractedRoot.listDirectoryEntries().firstOrNull { it.isDirectory() }
                ?: throw IOException("CEF archive had no top-level directory")

        val libSource = if (os == "osx") topLevel / "Contents" / "Home" / "lib" else topLevel / "lib"
        if (!libSource.exists()) throw IOException("CEF archive missing lib/ directory")
        placeDirectory(libSource, cefDir / "lib")

        if (os == "osx") {
            val frameworks = topLevel / "Contents" / "Frameworks"
            if (frameworks.exists()) {
                placeDirectory(frameworks, cefDir / "Frameworks")
            }
        }
    }

    /**
     * Moves [source] to [target], replacing whatever an interrupted install left there. A rename is
     * tried first; moving a non-empty directory across file systems throws
     * [java.nio.file.DirectoryNotEmptyException], so that case falls back to copy + delete.
     */
    private fun placeDirectory(
        source: java.nio.file.Path,
        target: java.nio.file.Path,
    ) {
        target.toFile().deleteRecursively()
        target.parent?.createDirectories()
        try {
            Files.move(source, target)
        } catch (_: java.nio.file.DirectoryNotEmptyException) {
            copyTree(source, target)
            source.toFile().deleteRecursively()
        } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
            copyTree(source, target)
            source.toFile().deleteRecursively()
        }
    }

    private fun copyTree(
        source: java.nio.file.Path,
        target: java.nio.file.Path,
    ) {
        Files.walk(source).use { paths ->
            paths.forEach { path ->
                val dest = target.resolve(source.relativize(path).toString())
                when {
                    Files.isSymbolicLink(path) -> {
                        dest.parent?.createDirectories()
                        Files.deleteIfExists(dest)
                        Files.createSymbolicLink(dest, Files.readSymbolicLink(path))
                    }
                    Files.isDirectory(path) -> dest.createDirectories()
                    else -> {
                        dest.parent?.createDirectories()
                        Files.copy(
                            path,
                            dest,
                            java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                            java.nio.file.StandardCopyOption.COPY_ATTRIBUTES,
                        )
                    }
                }
            }
        }
    }

    class CefException(
        msg: String,
    ) : Exception(msg)
}
