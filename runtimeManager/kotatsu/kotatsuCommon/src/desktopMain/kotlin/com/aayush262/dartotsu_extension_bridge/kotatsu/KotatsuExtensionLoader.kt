package com.aayush262.dartotsu_extension_bridge.kotatsu

import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.aayush262.dartotsu_extension_bridge.network.BridgeWebView
import com.aayush262.dartotsu_extension_bridge.network.FlutterCookieJar
import com.aayush262.dartotsu_extension_bridge.network.Network
import com.aayush262.dartotsu_extension_bridge.network.NetworkBound
import com.aayush262.dartotsu_extension_bridge.util.PackageTools
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.koitharu.kotatsu.parsers.InternalParsersApi
import org.koitharu.kotatsu.parsers.MangaLoaderContext
import org.koitharu.kotatsu.parsers.MangaParser
import org.koitharu.kotatsu.parsers.bitmap.Bitmap
import org.koitharu.kotatsu.parsers.bitmap.Rect
import org.koitharu.kotatsu.parsers.config.ConfigKey
import org.koitharu.kotatsu.parsers.config.MangaSourceConfig
import org.koitharu.kotatsu.parsers.model.ContentType
import org.koitharu.kotatsu.parsers.model.Manga
import org.koitharu.kotatsu.parsers.model.MangaChapter
import org.koitharu.kotatsu.parsers.model.MangaListFilter
import org.koitharu.kotatsu.parsers.model.MangaSource
import org.koitharu.kotatsu.parsers.model.MangaState
import org.koitharu.kotatsu.parsers.model.SortOrder
import java.awt.image.BufferedImage
import java.io.ByteArrayOutputStream
import java.io.File
import java.lang.reflect.Modifier
import java.net.URLClassLoader
import java.util.concurrent.ConcurrentHashMap
import java.util.zip.ZipFile
import javax.imageio.ImageIO

/**
 * Loads a parsers jar with its own copy of the parsers API (core, model, ...), so a jar built
 * against a newer API than the one vendored here still links. Only the types the bridge hands
 * in (context, config, bitmaps, MangaSource) and the shared libraries come from the bridge.
 */
class KotatsuDesktopPluginClassLoader(url: java.net.URL, parent: ClassLoader) : URLClassLoader(arrayOf(url), parent) {
    private fun shared(name: String) =
        name.startsWith("org.koitharu.kotatsu.parsers.bitmap.") ||
            name.startsWith("org.koitharu.kotatsu.parsers.config.") ||
            name.startsWith("org.koitharu.kotatsu.parsers.webview.") ||
            name == "org.koitharu.kotatsu.parsers.MangaLoaderContext" ||
            name == "org.koitharu.kotatsu.parsers.model.MangaSource" ||
            name == "org.koitharu.kotatsu.parsers.model.ContentType" ||
            !name.startsWith("org.koitharu.kotatsu.")

    override fun loadClass(name: String, resolve: Boolean): Class<*> {
        if (shared(name)) {
            return try {
                super.loadClass(name, resolve)
            } catch (e: ClassNotFoundException) {
                if (name.startsWith("org.koitharu.kotatsu.")) throw e
                findClass(name)
            }
        }
        synchronized(getClassLoadingLock(name)) {
            val c = findLoadedClass(name) ?: try {
                findClass(name)
            } catch (_: ClassNotFoundException) {
                return super.loadClass(name, resolve)
            }
            if (resolve) resolveClass(c)
            return c
        }
    }
}

@OptIn(InternalParsersApi::class)
actual object KotatsuExtensionLoader {
    private val loadedParsers = ConcurrentHashMap<String, MangaParser>()
    private val classLoaders = ConcurrentHashMap<String, URLClassLoader>()
    private val sourceIdToClassName = ConcurrentHashMap<String, String>()
    private val scanMutex = Mutex()

    private class DesktopBitmap(val image: BufferedImage) : Bitmap {
        override val width: Int get() = image.width
        override val height: Int get() = image.height
        override fun drawBitmap(sourceBitmap: Bitmap, src: Rect, dst: Rect) {
            val srcImage = (sourceBitmap as DesktopBitmap).image
            val g = image.createGraphics()
            try {
                g.drawImage(
                    srcImage,
                    dst.left, dst.top, dst.right, dst.bottom,
                    src.left, src.top, src.right, src.bottom,
                    null,
                )
            } finally {
                g.dispose()
            }
        }
    }

    private object DesktopMangaLoaderContext : MangaLoaderContext() {
        override val cookieJar: CookieJar = FlutterCookieJar

        private val client = NetworkBound {
            Network.applyTo(OkHttpClient.Builder().cookieJar(cookieJar), mergeCookies = false).build()
        }

        override val httpClient: OkHttpClient
            get() = client.get()

        override fun newParserInstance(source: MangaSource): MangaParser =
            throw UnsupportedOperationException("Context doesn't instantiate parsers directly")

        override fun getParserSources(): List<MangaSource> = loadedParsers.values.map { it.source }

        @Deprecated("Provide a base url")
        override suspend fun evaluateJs(script: String): String? = evaluateJs("about:blank", script)
        override suspend fun evaluateJs(baseUrl: String, script: String): String? =
            withContext(Dispatchers.IO) { BridgeWebView.evaluate(baseUrl, script) }

        override fun getConfig(source: MangaSource): MangaSourceConfig = object : MangaSourceConfig {
            override fun <T> get(key: ConfigKey<T>): T = key.defaultValue
        }

        override fun getDefaultUserAgent(): String = Network.userAgent

        override fun redrawImageResponse(response: Response, redraw: (image: Bitmap) -> Bitmap): Response {
            val body = response.body
            return try {
                val bytes = body.bytes()
                val srcImage = ImageIO.read(bytes.inputStream()) ?: return response
                val dstImage = (redraw(DesktopBitmap(srcImage)) as DesktopBitmap).image
                val out = ByteArrayOutputStream()
                ImageIO.write(dstImage, "png", out)
                response.newBuilder()
                    .body(out.toByteArray().toResponseBody(body.contentType()))
                    .build()
            } catch (e: Exception) {
                Logger.log("[Kotatsu-Desktop] Redraw image response failed: ${e.message}")
                response
            }
        }

        override fun createBitmap(width: Int, height: Int): Bitmap =
            DesktopBitmap(BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB))
    }

    private fun getPageSize(parser: MangaParser): Int = try {
        parser.javaClass.getField("pageSize").get(parser) as Int
    } catch (e: Exception) {
        try {
            parser.javaClass.getDeclaredField("pageSize").apply { isAccessible = true }.get(parser) as Int
        } catch (e2: Exception) {
            20
        }
    }

    private fun getOrLoadParser(sourceId: String): MangaParser? {
        loadedParsers[sourceId]?.let { return it }
        val className = sourceIdToClassName[sourceId] ?: return null
        for (classLoader in classLoaders.values) {
            try {
                val clazz = classLoader.loadClass(className)
                val parser = instantiateParser(clazz, classLoader) ?: continue
                loadedParsers[sourceId] = parser
                return parser
            } catch (_: Exception) {
            }
        }
        return null
    }

    private var instantiateFailures = 0

    private fun instantiateParser(clazz: Class<*>, loader: ClassLoader): MangaParser? {
        if (!loader.loadClass("org.koitharu.kotatsu.parsers.MangaParser").isAssignableFrom(clazz)) return null
        if (clazz.isInterface || Modifier.isAbstract(clazz.modifiers)) return null
        // The wrapper takes a delegate, it is not a source.
        if (clazz.name == "org.koitharu.kotatsu.parsers.core.MangaParserWrapper") return null
        val raw = try {
            clazz.getDeclaredConstructor(MangaLoaderContext::class.java).newInstance(DesktopMangaLoaderContext)
        } catch (e: Throwable) {
            try {
                clazz.getDeclaredConstructor().newInstance()
            } catch (_: Throwable) {
                // Report why the real constructor failed; the no-arg fallback's
                // NoSuchMethodException says nothing. Only the first few, a broken jar
                // fails for every class.
                if (instantiateFailures++ < 5) {
                    val cause = (e as? java.lang.reflect.InvocationTargetException)?.targetException ?: e
                    Logger.log("[Kotatsu-Desktop] Failed to instantiate ${clazz.name}: ${cause.javaClass.simpleName}: ${cause.message}")
                }
                return null
            }
        }
        return KotatsuMangaParserWrapper(raw, loader)
    }

    actual suspend fun loadExtensions(folderPath: String?): List<Map<String, Any?>> = scanMutex.withLock {
        withContext(Dispatchers.IO) {
            val path = folderPath ?: return@withContext emptyList()
            instantiateFailures = 0
            val folder = File(path)
            if (!folder.exists() || !folder.isDirectory) return@withContext emptyList()

            val jars = folder.listFiles { f ->
                f.isFile && (
                    f.name == "plugin.jar" || f.name == "kotatsu_plugin.jar" ||
                        (f.extension == "jar" && f.name.contains("kotatsu"))
                    )
            }.orEmpty().sortedByDescending { it.lastModified() }

            val convertedDir = File(folder, "converted").apply { mkdirs() }
            val list = mutableListOf<Map<String, Any?>>()
            // Several repos can ship the same source; the newest jar's copy wins.
            val seen = HashSet<String>()

            for (jar in jars) {
                try {
                    val hasDex = ZipFile(jar).use { zf ->
                        zf.entries().asSequence().any { it.name.startsWith("classes") && it.name.endsWith(".dex") }
                    }

                    val jarToLoad = if (hasDex) {
                        val converted = File(convertedDir, "${jar.nameWithoutExtension}.converted.jar")
                        if (!converted.exists() || jar.lastModified() > converted.lastModified()) {
                            Logger.log("[Kotatsu-Desktop] Converting ${jar.name} via dex2jar...")
                            PackageTools.dex2jar(jar.absolutePath, converted.absolutePath)
                            // converted.absolutePath is stable across repo jar
                            // updates - drop any classloader cached for it from
                            // a previous version so classes are re-read fresh.
                            PackageTools.invalidateClassLoader(converted.absolutePath)
                        }
                        converted
                    } else {
                        jar
                    }

                    val classLoader = KotatsuDesktopPluginClassLoader(
                        jarToLoad.toURI().toURL(),
                        KotatsuExtensionLoader::class.java.classLoader,
                    )
                    classLoaders[jarToLoad.absolutePath] = classLoader

                    val classNames = ZipFile(jarToLoad).use { zf ->
                        zf.entries().asSequence()
                            .filter { it.name.endsWith(".class") && !it.name.contains("$") }
                            .map { it.name.removeSuffix(".class").replace('/', '.') }
                            .toList()
                    }

                    for (className in classNames) {
                        try {
                            val clazz = classLoader.loadClass(className)
                            val parser = instantiateParser(clazz, classLoader) ?: continue
                            val source = parser.source
                            // Distinct sources can differ only by punctuation (LUNAR_SCAN vs
                            // LUNARSCAN); stripping it collapsed them onto one id and caused
                            // duplicate-key crashes in the list UI.
                            val idStr = "kotatsu_" + source.name.lowercase()
                            if (!seen.add(idStr)) continue
                            loadedParsers[idStr] = parser
                            sourceIdToClassName[idStr] = className

                            val cleanDomain = try {
                                parser.domain.replace("https://", "").replace("http://", "").split("/")[0]
                            } catch (_: Exception) {
                                ""
                            }
                            val iconUrl = if (cleanDomain.isNotEmpty()) {
                                "https://www.google.com/s2/favicons?sz=128&domain=$cleanDomain"
                            } else {
                                "https://raw.githubusercontent.com/KotatsuApp/Kotatsu/devel/metadata/en-US/icon.png"
                            }

                            list.add(
                                mapOf(
                                    "id" to idStr,
                                    "name" to source.title,
                                    "lang" to source.locale.ifEmpty { "all" },
                                    "type" to "manga",
                                    "baseUrl" to parser.domain,
                                    "iconUrl" to iconUrl,
                                    "isNsfw" to (source.contentType == ContentType.HENTAI),
                                    "version" to "1.0.0",
                                    "pkgName" to "kotatsu.plugin",
                                    "className" to className,
                                    "itemType" to 0,
                                    "hasUpdate" to false,
                                    "isObsolete" to false,
                                    "isShared" to false,
                                ),
                            )
                        } catch (_: Throwable) {
                        }
                    }
                } catch (e: Exception) {
                    Logger.log("[Kotatsu-Desktop] Error processing ${jar.name}: ${e.message}")
                }
            }

            Logger.log("[Kotatsu-Desktop] Scan complete. Found ${list.size} sources.")
            list
        }
    }

    actual suspend fun getPopular(sourceId: String, page: Int): Map<String, Any?> = withContext(Dispatchers.IO) {
        val parser = getOrLoadParser(sourceId)
            ?: return@withContext mapOf("list" to emptyList<Any>(), "hasNextPage" to false)
        try {
            val offset = (page - 1) * getPageSize(parser)
            val mangaList = parser.getList(offset, SortOrder.POPULARITY, MangaListFilter.EMPTY)
            mapOf(
                "list" to mangaList.map { mapOf("title" to it.title, "url" to it.url, "cover" to it.coverUrl) },
                "hasNextPage" to mangaList.isNotEmpty(),
            )
        } catch (e: Exception) {
            Logger.log("[Kotatsu-Desktop] getPopular failed for $sourceId: ${e.message}")
            mapOf("list" to emptyList<Any>(), "hasNextPage" to false)
        }
    }

    actual suspend fun getLatestUpdates(sourceId: String, page: Int): Map<String, Any?> = withContext(Dispatchers.IO) {
        val parser = getOrLoadParser(sourceId)
            ?: return@withContext mapOf("list" to emptyList<Any>(), "hasNextPage" to false)
        try {
            val offset = (page - 1) * getPageSize(parser)
            val mangaList = parser.getList(offset, SortOrder.UPDATED, MangaListFilter.EMPTY)
            mapOf(
                "list" to mangaList.map { mapOf("title" to it.title, "url" to it.url, "cover" to it.coverUrl) },
                "hasNextPage" to mangaList.isNotEmpty(),
            )
        } catch (e: Exception) {
            Logger.log("[Kotatsu-Desktop] getLatestUpdates failed for $sourceId: ${e.message}")
            mapOf("list" to emptyList<Any>(), "hasNextPage" to false)
        }
    }

    actual suspend fun search(sourceId: String, query: String, page: Int): Map<String, Any?> = withContext(Dispatchers.IO) {
        val parser = getOrLoadParser(sourceId)
            ?: return@withContext mapOf("list" to emptyList<Any>(), "hasNextPage" to false)
        try {
            val offset = (page - 1) * getPageSize(parser)
            val mangaList = parser.getList(offset, SortOrder.RELEVANCE, MangaListFilter(query = query))
            mapOf(
                "list" to mangaList.map { mapOf("title" to it.title, "url" to it.url, "cover" to it.coverUrl) },
                "hasNextPage" to mangaList.isNotEmpty(),
            )
        } catch (e: Exception) {
            Logger.log("[Kotatsu-Desktop] search failed for $sourceId: ${e.message}")
            mapOf("list" to emptyList<Any>(), "hasNextPage" to false)
        }
    }

    actual suspend fun getDetails(sourceId: String, url: String, title: String, cover: String): Map<String, Any?> = withContext(Dispatchers.IO) {
        val parser = getOrLoadParser(sourceId) ?: return@withContext emptyMap()
        try {
            val dummyManga = Manga(
                id = 0L,
                title = title,
                altTitles = emptySet(),
                url = url,
                publicUrl = "",
                rating = 0f,
                contentRating = null,
                coverUrl = cover,
                tags = emptySet(),
                state = null,
                authors = emptySet(),
                source = parser.source,
            )
            val details = parser.getDetails(dummyManga)
            val chapters = details.chapters.orEmpty()
            val mappedChapters = chapters.map { ch ->
                mapOf(
                    "name" to (ch.title ?: "Chapter ${ch.number}"),
                    "url" to ch.url,
                    "chapter_number" to ch.number,
                    "episode_number" to ch.number,
                    "date_upload" to ch.uploadDate,
                    "scanlator" to (ch.scanlator ?: ""),
                )
            }
            val statusVal = when (details.state) {
                MangaState.ONGOING -> 1
                MangaState.FINISHED -> 2
                else -> 0
            }
            mapOf(
                "title" to details.title,
                "url" to details.url,
                "cover" to (details.largeCoverUrl ?: details.coverUrl ?: cover),
                "description" to (details.description ?: ""),
                "author" to (details.authors.firstOrNull() ?: ""),
                "artist" to "",
                "genre" to details.tags.map { it.title },
                "status" to statusVal,
                "episodes" to mappedChapters,
            )
        } catch (e: Exception) {
            Logger.log("[Kotatsu-Desktop] getDetails failed for $sourceId: ${e.message}")
            emptyMap()
        }
    }

    actual suspend fun getPageList(sourceId: String, url: String, name: String): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        val parser = getOrLoadParser(sourceId) ?: return@withContext emptyList()
        try {
            val dummyChapter = MangaChapter(
                id = 0L,
                title = name,
                number = 0f,
                volume = 0,
                url = url,
                scanlator = null,
                uploadDate = 0L,
                branch = null,
                source = parser.source,
            )
            val pages = parser.getPages(dummyChapter)
            val pageUrls = coroutineScope {
                pages.map { page ->
                    async {
                        try {
                            parser.getPageUrl(page)
                        } catch (e: Exception) {
                            page.url
                        }
                    }
                }.map { it.await() }
            }

            val headers = try {
                parser.getRequestHeaders().names().associateWith { parser.getRequestHeaders()[it] ?: "" }
            } catch (_: Exception) {
                emptyMap()
            }

            pageUrls.map { mapOf("url" to it, "headers" to headers) }
        } catch (e: Exception) {
            Logger.log("[Kotatsu-Desktop] getPageList failed for $sourceId: ${e.message}")
            emptyList()
        }
    }
}
