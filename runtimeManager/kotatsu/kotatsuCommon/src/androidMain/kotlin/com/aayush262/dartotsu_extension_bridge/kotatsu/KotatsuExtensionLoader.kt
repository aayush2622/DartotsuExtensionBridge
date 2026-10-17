@file:Suppress("DEPRECATION")
@file:OptIn(InternalParsersApi::class)

package com.aayush262.dartotsu_extension_bridge.kotatsu

import com.aayush262.dartotsu_extension_bridge.network.BridgeWebView
import com.aayush262.dartotsu_extension_bridge.network.FlutterCookieJar
import com.aayush262.dartotsu_extension_bridge.network.Network
import com.aayush262.dartotsu_extension_bridge.network.NetworkBound
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.webkit.CookieManager
import dalvik.system.DexClassLoader
import okhttp3.CookieJar
import okhttp3.Cookie
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.ResponseBody
import okhttp3.Headers
import org.koitharu.kotatsu.parsers.MangaLoaderContext
import org.koitharu.kotatsu.parsers.MangaParser
import org.koitharu.kotatsu.parsers.bitmap.Bitmap
import org.koitharu.kotatsu.parsers.bitmap.Rect
import org.koitharu.kotatsu.parsers.config.ConfigKey
import org.koitharu.kotatsu.parsers.config.MangaSourceConfig
import org.koitharu.kotatsu.parsers.model.*
import org.koitharu.kotatsu.parsers.model.search.MangaSearchQuery
import org.koitharu.kotatsu.parsers.model.search.MangaSearchQueryCapabilities
import java.io.File
import java.io.ByteArrayOutputStream
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.zip.ZipFile
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.Interceptor
import org.json.JSONArray
import org.json.JSONObject
import org.koitharu.kotatsu.parsers.InternalParsersApi
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method
import java.lang.reflect.Modifier
import kotlin.collections.iterator
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

class KotatsuAndroidPluginClassLoader(
    dexPath: String,
    optimizedDirectory: String,
    librarySearchPath: String?,
    parent: ClassLoader
) : DexClassLoader(dexPath, optimizedDirectory, librarySearchPath, parent) {

    override fun loadClass(name: String, resolve: Boolean): Class<*> {
        val shouldDelegate = name.startsWith("org.koitharu.kotatsu.parsers.bitmap.") ||
                name.startsWith("org.koitharu.kotatsu.parsers.webview.") ||
                name.startsWith("org.koitharu.kotatsu.parsers.config.") ||
                name == "org.koitharu.kotatsu.parsers.MangaLoaderContext" ||
                name == "org.koitharu.kotatsu.parsers.model.MangaSource" ||
                name == "org.koitharu.kotatsu.parsers.model.ContentType" ||
                name.startsWith("okhttp3.") ||
                name.startsWith("okio.") ||
                name.startsWith("kotlin.") ||
                name.startsWith("java.") ||
                name.startsWith("javax.") ||
                name.startsWith("org.jsoup.") ||
                name.startsWith("org.json.")

        if (shouldDelegate) {
            return super.loadClass(name, resolve)
        }

        val loaded = findLoadedClass(name)
        if (loaded != null) {
            return loaded
        }

        return try {
            findClass(name)
        } catch (e: ClassNotFoundException) {
            super.loadClass(name, resolve)
        }
    }
}

actual object KotatsuExtensionLoader {
    val loadedParsers = ConcurrentHashMap<String, MangaParser>()
    private val classLoaders = ConcurrentHashMap<String, DexClassLoader>()
    private val scanMutex = Mutex()
    private var initialized = false
    private val sourceIdToClassName = ConcurrentHashMap<String, String>()

    fun getOrLoadParser(sourceId: String): MangaParser? {
        val loaded = loadedParsers[sourceId]
        if (loaded != null) return loaded

        synchronized(loadedParsers) {
            val loadedDoubleCheck = loadedParsers[sourceId]
            if (loadedDoubleCheck != null) return loadedDoubleCheck

            val className = sourceIdToClassName[sourceId] ?: return null
            for (classLoader in classLoaders.values) {
                try {
                    val clazz = classLoader.loadClass(className)
                    val mangaParserClass = classLoader.loadClass("org.koitharu.kotatsu.parsers.MangaParser")
                    if (mangaParserClass.isAssignableFrom(clazz)) {
                        val rawParser = try {
                            clazz.getDeclaredConstructor(MangaLoaderContext::class.java).newInstance(AndroidMangaLoaderContext)
                        } catch (e: Exception) {
                            clazz.getDeclaredConstructor().newInstance()
                        }
                        val parserInstance = KotatsuMangaParserWrapper(rawParser, classLoader)
                        loadedParsers[sourceId] = parserInstance
                        System.err.println("[Kotatsu-Android] Lazily loaded parser: ${parserInstance.source.title} ($sourceId)")
                        return parserInstance
                    }
                } catch (e: Exception) {
                }
            }
        }
        return null
    }

    fun initialize(context: Context) {
        if (initialized) return
        initialized = true
        System.err.println("[Kotatsu-Android] Kotatsu runtime context initialized!")
    }

    class AndroidBitmap(val bitmap: android.graphics.Bitmap) : Bitmap {
        override val width: Int get() = bitmap.width
        override val height: Int get() = bitmap.height
        override fun drawBitmap(sourceBitmap: Bitmap, src: Rect, dst: Rect) {
            val srcBmp = (sourceBitmap as AndroidBitmap).bitmap
            val canvas = Canvas(bitmap)
            val srcRect = android.graphics.Rect(src.left, src.top, src.right, src.bottom)
            val dstRect = android.graphics.Rect(dst.left, dst.top, dst.right, dst.bottom)
            canvas.drawBitmap(srcBmp, srcRect, dstRect, null)
        }
    }

    object AndroidMangaLoaderContext : MangaLoaderContext() {
        override val cookieJar: CookieJar = FlutterCookieJar

        private val client = NetworkBound {
            Network.applyTo(OkHttpClient.Builder().cookieJar(cookieJar), mergeCookies = false).build()
        }

        override val httpClient: OkHttpClient
            get() = client.get()

        override fun newParserInstance(source: MangaSource): MangaParser {
            throw UnsupportedOperationException("Context doesn't instantiate parsers directly")
        }

        override fun getParserSources(): List<MangaSource> {
            return loadedParsers.values.map { it.source }
        }

        @Deprecated("Provide a base url")
        override suspend fun evaluateJs(script: String): String? = evaluateJs("about:blank", script)
        override suspend fun evaluateJs(baseUrl: String, script: String): String? =
            withContext(Dispatchers.IO) { BridgeWebView.evaluate(baseUrl, script) }

        override fun getConfig(source: MangaSource): MangaSourceConfig {
            return object : MangaSourceConfig {
                override fun <T> get(key: ConfigKey<T>): T {
                    return key.defaultValue
                }
            }
        }

        override fun getDefaultUserAgent(): String = Network.userAgent

        override fun redrawImageResponse(response: Response, redraw: (image: Bitmap) -> Bitmap): Response {
            val body = response.body
            return try {
                val bytes = body.bytes()
                val androidBmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return response
                val mutableBmp = androidBmp.copy(android.graphics.Bitmap.Config.ARGB_8888, true)
                val srcBitmap = AndroidBitmap(mutableBmp)
                val dstBitmap = redraw(srcBitmap) as AndroidBitmap
                val bos = ByteArrayOutputStream()
                dstBitmap.bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, bos)
                val newBody = ResponseBody.create(body.contentType(), bos.toByteArray())
                response.newBuilder().body(newBody).build()
            } catch (e: Exception) {
                System.err.println("[Kotatsu-Android] Redraw image response failed: ${e.message}")
                response
            }
        }

        override fun createBitmap(width: Int, height: Int): Bitmap {
            val config = android.graphics.Bitmap.Config.ARGB_8888
            val bmp = android.graphics.Bitmap.createBitmap(width, height, config)
            return AndroidBitmap(bmp)
        }
    }

    private fun getPageSize(parser: MangaParser): Int {
        return try {
            val field = parser.javaClass.getField("pageSize")
            field.get(parser) as Int
        } catch (e: Exception) {
            try {
                val field = parser.javaClass.getDeclaredField("pageSize")
                field.isAccessible = true
                field.get(parser) as Int
            } catch (e2: Exception) {
                20
            }
        }
    }

    actual suspend fun loadExtensions(folderPath: String?): List<Map<String, Any?>> {
        val context = Injekt.get<Context>()
        return scanMutex.withLock {
            initialize(context)
            val path = folderPath ?: context.filesDir.absolutePath
            val folder = File(path)
            if (!folder.exists() || !folder.isDirectory) return@withLock emptyList()

            val cacheFile = File(folder, "kotatsu_extensions_cache.json")
            if (cacheFile.exists()) {
                try {
                    val cachedText = cacheFile.readText()
                    val jsonArray = JSONArray(cachedText)
                    val cachedList = mutableListOf<Map<String, Any?>>()

                    folder.listFiles { file -> file.name == "plugin.jar" || file.name == "kotatsu_plugin.jar" || (file.extension == "jar" && file.name.contains("kotatsu")) }?.forEach { jar ->
                        try {
                            val tempJar = File(context.cacheDir, "kotatsu_${jar.name}")
                            if (tempJar.exists()) {
                                tempJar.setWritable(true)
                                tempJar.delete()
                            }
                            jar.copyTo(tempJar, overwrite = true)
                            tempJar.setReadOnly()
                            val classLoader = KotatsuAndroidPluginClassLoader(
                                tempJar.absolutePath,
                                context.cacheDir.absolutePath,
                                null,
                                KotatsuExtensionLoader::class.java.classLoader!!
                            )
                            classLoaders[jar.absolutePath] = classLoader
                        } catch (e: Exception) {
                            System.err.println("[Kotatsu-Android] Error initializing classloader from cache flow: ${e.message}")
                        }
                    }

                    for (i in 0 until jsonArray.length()) {
                        val obj = jsonArray.getJSONObject(i)
                        val map = mutableMapOf<String, Any?>()
                        val keys = obj.keys()
                        while (keys.hasNext()) {
                            val key = keys.next()
                            val value = obj.get(key)
                            if (value == JSONObject.NULL) {
                                map[key] = null
                            } else {
                                map[key] = value
                            }
                        }
                        cachedList.add(map)

                        val idStr = map["id"] as? String
                        val className = map["className"] as? String
                        if (idStr != null && className != null) {
                            sourceIdToClassName[idStr] = className
                        }
                    }
                    System.err.println("[Kotatsu-Android] Loaded ${cachedList.size} sources from cache.")
                    return@withLock cachedList
                } catch (e: Exception) {
                    System.err.println("[Kotatsu-Android] Failed to load cache: ${e.message}. Rescanning...")
                }
            }

            val list = mutableListOf<Map<String, Any?>>()

            folder.listFiles { file -> file.name == "plugin.jar" || file.name == "kotatsu_plugin.jar" || (file.extension == "jar" && file.name.contains("kotatsu")) }?.forEach { jar ->
                System.err.println("[Kotatsu-Android] Scanning JAR: ${jar.name}")

                try {
                    val tempJar = File(context.cacheDir, "kotatsu_${jar.name}")
                    if (tempJar.exists()) {
                        tempJar.setWritable(true)
                        tempJar.delete()
                    }
                    jar.copyTo(tempJar, overwrite = true)
                    tempJar.setReadOnly()

                    val classLoader = KotatsuAndroidPluginClassLoader(
                        tempJar.absolutePath,
                        context.cacheDir.absolutePath,
                        null,
                        KotatsuExtensionLoader::class.java.classLoader!!
                    )

                    val classNames = mutableSetOf<String>()

                    fun extractClassNamesFromDex(bytes: ByteArray): List<String> {
                        val names = mutableListOf<String>()
                        try {
                            if (bytes.size < 112) return emptyList()
                            if (bytes[0].toInt() != 'd'.code || bytes[1].toInt() != 'e'.code || bytes[2].toInt() != 'x'.code) {
                                return emptyList()
                            }
                            fun readInt(offset: Int): Int {
                                return (bytes[offset].toInt() and 0xFF) or
                                        ((bytes[offset + 1].toInt() and 0xFF) shl 8) or
                                        ((bytes[offset + 2].toInt() and 0xFF) shl 16) or
                                        ((bytes[offset + 3].toInt() and 0xFF) shl 24)
                            }
                            val stringIdsSize = readInt(56)
                            val stringIdsOff = readInt(60)
                            val typeIdsSize = readInt(64)
                            val typeIdsOff = readInt(68)
                            val classDefsSize = readInt(96)
                            val classDefsOff = readInt(100)

                            for (i in 0 until classDefsSize) {
                                val classDefOffset = classDefsOff + i * 32
                                if (classDefOffset + 4 > bytes.size) break
                                val classIdx = readInt(classDefOffset)

                                if (classIdx >= typeIdsSize) continue
                                val typeOffset = typeIdsOff + classIdx * 4
                                if (typeOffset + 4 > bytes.size) continue
                                val descriptorIdx = readInt(typeOffset)

                                if (descriptorIdx >= stringIdsSize) continue
                                val stringOffsetOffset = stringIdsOff + descriptorIdx * 4
                                if (stringOffsetOffset + 4 > bytes.size) continue
                                val stringDataOff = readInt(stringOffsetOffset)

                                if (stringDataOff >= bytes.size) continue

                                var offset = stringDataOff
                                var value = 0
                                var shift = 0
                                while (offset < bytes.size) {
                                    val b = bytes[offset++].toInt() and 0xFF
                                    value = value or ((b and 0x7F) shl shift)
                                    if ((b and 0x80) == 0) break
                                    shift += 7
                                }

                                val start = offset
                                while (offset < bytes.size && bytes[offset] != 0.toByte()) {
                                    offset++
                                }

                                if (offset > start) {
                                    val stringBytes = bytes.copyOfRange(start, offset)
                                    val descriptor = String(stringBytes, Charsets.UTF_8)
                                    if (descriptor.startsWith("L") && descriptor.endsWith(";")) {
                                        val className = descriptor.substring(1, descriptor.length - 1).replace('/', '.')
                                        names.add(className)
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            System.err.println("[Kotatsu-Android] Error parsing DEX: ${e.message}")
                        }
                        return names
                    }

                    try {
                        val zipFile = ZipFile(tempJar)
                        for (entry in zipFile.entries()) {
                            if (entry.name.startsWith("classes") && entry.name.endsWith(".dex")) {
                                zipFile.getInputStream(entry).use { inputStream ->
                                    val bytes = inputStream.readBytes()
                                    classNames.addAll(extractClassNamesFromDex(bytes))
                                }
                            } else if (entry.name.endsWith(".class") && !entry.name.contains("$")) {
                                classNames.add(entry.name.replace("/", ".").removeSuffix(".class"))
                            }
                        }
                        zipFile.close()
                    } catch (e: Exception) {
                        System.err.println("[Kotatsu-Android] Failed to scan zip/dex entries: ${e.message}")
                        e.printStackTrace(System.err)
                    }

                    var errorCount = 0
                    val maxErrorsToLog = 5
                    for (className in classNames) {
                        try {
                            val clazz = classLoader.loadClass(className)
                            val mangaParserClass = classLoader.loadClass("org.koitharu.kotatsu.parsers.MangaParser")
                            val isMangaParser = mangaParserClass.isAssignableFrom(clazz)
                            if (isMangaParser &&
                                !clazz.isInterface &&
                                !Modifier.isAbstract(clazz.modifiers)) {

                                val rawParser = try {
                                    clazz.getDeclaredConstructor(MangaLoaderContext::class.java).newInstance(AndroidMangaLoaderContext)
                                } catch (e: Exception) {
                                    val realException = if (e is InvocationTargetException) e.targetException else e
                                    if (errorCount < maxErrorsToLog) {
                                        System.err.println("  [Kotatsu-Android] Failed to instantiate with MangaLoaderContext constructor for $className: ${realException.message} (${realException.javaClass.name})")
                                        realException.printStackTrace(System.err)
                                    }
                                    clazz.getDeclaredConstructor().newInstance()
                                }

                                val parserInstance = KotatsuMangaParserWrapper(rawParser, classLoader)
                                val source = parserInstance.source
                                // source.name is a MangaParserSource enum constant name, which
                                // the Kotlin compiler already guarantees is unique - stripping
                                // non-alphanumeric characters (the "_" in e.g. LUNAR_SCAN vs
                                // LUNARSCAN) before lowercasing collapsed distinct sources onto
                                // the same id, causing duplicate-GlobalKey crashes in the list UI.
                                val idStr = "kotatsu_" + source.name.lowercase()
                                loadedParsers[idStr] = parserInstance
                                sourceIdToClassName[idStr] = className

                                System.err.println("  [Kotatsu-Android] Found Parser: ${source.title} ($idStr)")

                                val cleanDomain = try {
                                    parserInstance.domain
                                        .replace("https://", "")
                                        .replace("http://", "")
                                        .split("/")[0]
                                } catch (e: Exception) {
                                    ""
                                }
                                val iconUrl = if (cleanDomain.isNotEmpty()) {
                                    "https://www.google.com/s2/favicons?sz=128&domain=$cleanDomain"
                                } else {
                                    "https://raw.githubusercontent.com/KotatsuApp/Kotatsu/devel/metadata/en-US/icon.png"
                                }

                                val extObj = mapOf(
                                    "id" to idStr,
                                    "name" to source.title,
                                    "lang" to source.locale.ifEmpty { "all" },
                                    "type" to "manga",
                                    "baseUrl" to parserInstance.domain,
                                    "iconUrl" to iconUrl,
                                    "isNsfw" to (source.contentType == ContentType.HENTAI),
                                    "version" to "1.0.0",
                                    "pkgName" to "kotatsu.plugin",
                                    "className" to className,
                                    "itemType" to 0,
                                    "hasUpdate" to false,
                                    "isObsolete" to false,
                                    "isShared" to false
                                )
                                list.add(extObj)
                            }
                        } catch (e: Throwable) {
                            errorCount++
                            if (errorCount <= maxErrorsToLog) {
                                System.err.println("  [Kotatsu-Android] Failed to load/verify class $className: ${e.message} (${e.javaClass.name})")
                            }
                        }
                    }
                    if (errorCount > maxErrorsToLog) {
                        System.err.println("  [Kotatsu-Android] ... and ${errorCount - maxErrorsToLog} more class loading/instantiation errors omitted.")
                    }
                    classLoaders[jar.absolutePath] = classLoader
                } catch (e: Throwable) {
                    System.err.println("  [Kotatsu-Android] Error processing ${jar.name}: ${e.message}")
                }
            }

            System.err.println("[Kotatsu-Android] Scan complete. Found ${list.size} sources.")

            try {
                val jsonArr = JSONArray()
                for (item in list) {
                    val jsonObj = JSONObject(item)
                    jsonArr.put(jsonObj)
                }
                cacheFile.writeText(jsonArr.toString())
                System.err.println("[Kotatsu-Android] Saved cache to ${cacheFile.absolutePath}")
            } catch (e: Exception) {
                System.err.println("[Kotatsu-Android] Failed to save cache: ${e.message}")
            }

            list
        }
    }

    actual suspend fun getPopular(sourceId: String, page: Int): Map<String, Any?> = withContext(Dispatchers.IO) {
        val parser = getOrLoadParser(sourceId) ?: return@withContext mapOf("list" to emptyList<Any>(), "hasNextPage" to false)
        try {
            val offset = (page - 1) * getPageSize(parser)
            val list = parser.getList(offset, SortOrder.POPULARITY, MangaListFilter.EMPTY)
            val mappedList = list.map { m ->
                mapOf(
                    "title" to m.title,
                    "url" to m.url,
                    "cover" to m.coverUrl
                )
            }
            mapOf("list" to mappedList, "hasNextPage" to list.isNotEmpty())
        } catch (e: Exception) {
            e.printStackTrace()
            mapOf("list" to emptyList<Any>(), "hasNextPage" to false)
        }
    }

    actual suspend fun getLatestUpdates(sourceId: String, page: Int): Map<String, Any?> = withContext(Dispatchers.IO) {
        val parser = getOrLoadParser(sourceId) ?: return@withContext mapOf("list" to emptyList<Any>(), "hasNextPage" to false)
        try {
            val offset = (page - 1) * getPageSize(parser)
            val list = parser.getList(offset, SortOrder.UPDATED, MangaListFilter.EMPTY)
            val mappedList = list.map { m ->
                mapOf(
                    "title" to m.title,
                    "url" to m.url,
                    "cover" to m.coverUrl
                )
            }
            mapOf("list" to mappedList, "hasNextPage" to list.isNotEmpty())
        } catch (e: Exception) {
            e.printStackTrace()
            mapOf("list" to emptyList<Any>(), "hasNextPage" to false)
        }
    }

    actual suspend fun search(sourceId: String, query: String, page: Int): Map<String, Any?> = withContext(Dispatchers.IO) {
        val parser = getOrLoadParser(sourceId) ?: return@withContext mapOf("list" to emptyList<Any>(), "hasNextPage" to false)
        try {
            val offset = (page - 1) * getPageSize(parser)
            val filter = MangaListFilter(query = query)
            val list = parser.getList(offset, SortOrder.RELEVANCE, filter)
            val mappedList = list.map { m ->
                mapOf(
                    "title" to m.title,
                    "url" to m.url,
                    "cover" to m.coverUrl
                )
            }
            mapOf("list" to mappedList, "hasNextPage" to list.isNotEmpty())
        } catch (e: Exception) {
            e.printStackTrace()
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
                source = parser.source
            )
            val details = parser.getDetails(dummyManga)
            val chapters = details.chapters.orEmpty()
            val mappedChapters = chapters.map { ch ->
                val chNum = ch.number
                mapOf(
                    "name" to (ch.title ?: "Chapter $chNum"),
                    "url" to ch.url,
                    "chapter_number" to chNum,
                    "episode_number" to chNum,
                    "date_upload" to ch.uploadDate,
                    "scanlator" to (ch.scanlator ?: "")
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
                "episodes" to mappedChapters
            )
        } catch (e: Exception) {
            e.printStackTrace()
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
                source = parser.source
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
                }.awaitAll()
            }

            val headers = try {
                parser.getRequestHeaders().names().associateWith { parser.getRequestHeaders()[it] ?: "" }
            } catch (_: Exception) {
                emptyMap()
            }

            pageUrls.map { pUrl ->
                mapOf(
                    "url" to pUrl,
                    "headers" to headers
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
            emptyList()
        }
    }
}

