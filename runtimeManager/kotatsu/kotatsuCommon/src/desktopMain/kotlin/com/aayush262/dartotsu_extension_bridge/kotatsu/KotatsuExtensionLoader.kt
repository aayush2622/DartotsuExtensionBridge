package com.aayush262.dartotsu_extension_bridge.kotatsu

import com.aayush262.dartotsu_extension_bridge.logger.Logger
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
        override val cookieJar: CookieJar = object : CookieJar {
            private val store = ConcurrentHashMap<String, List<Cookie>>()
            override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
                store[url.host] = cookies
            }
            override fun loadForRequest(url: HttpUrl): List<Cookie> = store[url.host].orEmpty()
        }

        override val httpClient: OkHttpClient by lazy {
            OkHttpClient.Builder().cookieJar(cookieJar).build()
        }

        override suspend fun evaluateJs(script: String): String? = null

        override fun getConfig(source: MangaSource): MangaSourceConfig = object : MangaSourceConfig {
            override fun <T> get(key: ConfigKey<T>): T = key.defaultValue
        }

        override fun getDefaultUserAgent(): String =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

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
                if (!MangaParser::class.java.isAssignableFrom(clazz)) continue
                val parser = instantiateParser(clazz) ?: continue
                loadedParsers[sourceId] = parser
                return parser
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun instantiateParser(clazz: Class<*>): MangaParser? {
        if (clazz.isInterface || Modifier.isAbstract(clazz.modifiers)) return null
        val raw = try {
            clazz.getDeclaredConstructor(MangaLoaderContext::class.java).newInstance(DesktopMangaLoaderContext)
        } catch (e: Exception) {
            try {
                clazz.getDeclaredConstructor().newInstance()
            } catch (e2: Exception) {
                Logger.log("[Kotatsu-Desktop] Failed to instantiate ${clazz.name}: ${e2.message}")
                return null
            }
        }
        return raw as? MangaParser
    }

    actual suspend fun loadExtensions(folderPath: String?): List<Map<String, Any?>> = scanMutex.withLock {
        withContext(Dispatchers.IO) {
            val path = folderPath ?: return@withContext emptyList()
            val folder = File(path)
            if (!folder.exists() || !folder.isDirectory) return@withContext emptyList()

            val jars = folder.listFiles { f ->
                f.isFile && (
                    f.name == "plugin.jar" || f.name == "kotatsu_plugin.jar" ||
                        (f.extension == "jar" && f.name.contains("kotatsu"))
                    )
            }.orEmpty()

            val convertedDir = File(folder, "converted").apply { mkdirs() }
            val list = mutableListOf<Map<String, Any?>>()

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
                        }
                        converted
                    } else {
                        jar
                    }

                    val classLoader = PackageTools.getClassLoader(jarToLoad.absolutePath)
                    classLoaders[jarToLoad.absolutePath] = classLoader

                    val classNames = ZipFile(jarToLoad).use { zf ->
                        zf.entries().asSequence()
                            .filter { it.name.endsWith(".class") && !it.name.contains("$") }
                            .map { it.name.removeSuffix(".class").replace('/', '.') }
                            .toList()
                    }

                    var loadFailures = 0
                    var assignableCount = 0
                    var postInstantiateFailures = 0
                    val distinctFailures = LinkedHashMap<String, String>()
                    val distinctPostFailures = LinkedHashMap<String, String>()
                    for (className in classNames) {
                        try {
                            val clazz = try {
                                classLoader.loadClass(className)
                            } catch (e: Throwable) {
                                loadFailures++
                                distinctFailures["${e.javaClass.name}: ${e.message}"] = className
                                continue
                            }
                            if (!MangaParser::class.java.isAssignableFrom(clazz)) continue
                            assignableCount++

                            // instantiateParser() returns null for abstract/intermediate
                            // base classes (e.g. PagedMangaParser) as well as genuine
                            // failures - both are routine, not worth logging per class.
                            val parser = try {
                                instantiateParser(clazz)
                            } catch (_: Throwable) {
                                continue
                            } ?: continue
                            try {
                                val source = parser.source
                                // source.name is a MangaParserSource enum constant name, which
                                // the Kotlin compiler already guarantees is unique - stripping
                                // non-alphanumeric characters (the "_" in e.g. LUNAR_SCAN vs
                                // LUNARSCAN) before lowercasing collapsed distinct sources onto
                                // the same id, causing duplicate-GlobalKey crashes in the list UI.
                                val idStr = "kotatsu_" + source.name.lowercase()
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
                            } catch (e: Throwable) {
                                postInstantiateFailures++
                                distinctPostFailures["${e.javaClass.name}: ${e.message}"] = className
                            }
                        } catch (_: Throwable) {
                        }
                    }

                    Logger.log(
                        "[Kotatsu-Desktop] ${jar.name}: ${list.size}/${assignableCount} sources loaded " +
                            "($loadFailures class-load failures, $postInstantiateFailures incompatible parsers)",
                    )
                    // A load or post-instantiate failure means a class the JVM otherwise
                    // considers a real MangaParser couldn't actually be used - usually a
                    // binary-compatibility break between this jar's kotatsu-parsers build
                    // and the one this sidecar depends on. Log a sample so that's
                    // diagnosable instead of just silently missing sources.
                    for ((error, sampleClass) in distinctFailures) {
                        Logger.log("[Kotatsu-Desktop]   class-load failure: $error (e.g. $sampleClass)")
                    }
                    for ((error, sampleClass) in distinctPostFailures) {
                        Logger.log("[Kotatsu-Desktop]   incompatible parser: $error (e.g. $sampleClass)")
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
