@file:Suppress("DEPRECATION")
@file:OptIn(InternalParsersApi::class)

package com.aayush262.dartotsu_extension_bridge.kotatsu

import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
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
import uy.kohesive.injekt.api.get
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method
import java.lang.reflect.Modifier
import kotlin.collections.iterator
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

class KotatsuMangaParserWrapper(
    val rawParser: Any,
    val childClassLoader: ClassLoader
) : MangaParser {

    override fun intercept(chain: Interceptor.Chain): Response {
        return try {
            val interceptMethod = rawParser.javaClass.getMethod("intercept", Interceptor.Chain::class.java)
            interceptMethod.invoke(rawParser, chain) as Response
        } catch (e: Exception) {
            chain.proceed(chain.request())
        }
    }

    override val source: MangaSource by lazy {
        val rawSource = rawParser.javaClass.getMethod("getSource").invoke(rawParser)
        val name = try {
            rawSource.javaClass.getMethod("getName").invoke(rawSource) as String
        } catch (e: Exception) {
            try {
                rawSource.javaClass.getMethod("name").invoke(rawSource) as String
            } catch (ex: Exception) {
                rawSource.toString()
            }
        }
        val title = try {
            rawSource.javaClass.getMethod("getTitle").invoke(rawSource) as String
        } catch (e: Exception) {
            name
        }
        val locale = try {
            rawSource.javaClass.getMethod("getLocale").invoke(rawSource) as String
        } catch (e: Exception) {
            ""
        }
        val isBroken = try {
            rawSource.javaClass.getMethod("isBroken").invoke(rawSource) as Boolean
        } catch (e: Exception) {
            false
        }
        val contentTypeVal = try {
            val rawContentType = rawSource.javaClass.getMethod("getContentType").invoke(rawSource)
            val ctName = rawContentType.javaClass.getMethod("name").invoke(rawContentType) as String
            ContentType.valueOf(ctName)
        } catch (e: Exception) {
            ContentType.OTHER
        }

        object : MangaSource {
            override val name: String = name
            override val title: String = title
            override val locale: String = locale
            override val isBroken: Boolean = isBroken
            override val contentType: ContentType = contentTypeVal
        }
    }

    override val availableSortOrders: Set<SortOrder> by lazy {
        try {
            val rawSet = rawParser.javaClass.getMethod("getAvailableSortOrders").invoke(rawParser) as Set<*>
            rawSet.map { rawOrder ->
                val name = rawOrder!!.javaClass.getMethod("name").invoke(rawOrder) as String
                SortOrder.valueOf(name)
            }.toSet()
        } catch (e: Exception) {
            setOf(SortOrder.POPULARITY)
        }
    }

    @Deprecated("Too complex. Use filterCapabilities instead")
    override val searchQueryCapabilities: MangaSearchQueryCapabilities
        get() = throw UnsupportedOperationException()

    override val filterCapabilities: MangaListFilterCapabilities by lazy {
        try {
            val rawCap = rawParser.javaClass.getMethod("getFilterCapabilities").invoke(rawParser)
            val isMultipleTagsSupported = getFieldValue(rawCap, "isMultipleTagsSupported") as? Boolean ?: false
            val isTagsExclusionSupported = getFieldValue(rawCap, "isTagsExclusionSupported") as? Boolean ?: false
            val isSearchSupported = getFieldValue(rawCap, "isSearchSupported") as? Boolean ?: false
            val isSearchWithFiltersSupported = getFieldValue(rawCap, "isSearchWithFiltersSupported") as? Boolean ?: false
            val isYearSupported = getFieldValue(rawCap, "isYearSupported") as? Boolean ?: false
            val isYearRangeSupported = getFieldValue(rawCap, "isYearRangeSupported") as? Boolean ?: false
            val isOriginalLocaleSupported = getFieldValue(rawCap, "isOriginalLocaleSupported") as? Boolean ?: false
            val isAuthorSearchSupported = getFieldValue(rawCap, "isAuthorSearchSupported") as? Boolean ?: false

            MangaListFilterCapabilities(
                isMultipleTagsSupported = isMultipleTagsSupported,
                isTagsExclusionSupported = isTagsExclusionSupported,
                isSearchSupported = isSearchSupported,
                isSearchWithFiltersSupported = isSearchWithFiltersSupported,
                isYearSupported = isYearSupported,
                isYearRangeSupported = isYearRangeSupported,
                isOriginalLocaleSupported = isOriginalLocaleSupported,
                isAuthorSearchSupported = isAuthorSearchSupported
            )
        } catch (e: Exception) {
            MangaListFilterCapabilities(isSearchSupported = true)
        }
    }

    override val config: MangaSourceConfig
        get() {
            return object : MangaSourceConfig {
                override fun <T> get(key: ConfigKey<T>): T {
                    return key.defaultValue
                }
            }
        }

    override val configKeyDomain: ConfigKey.Domain
        get() = throw UnsupportedOperationException()

    override val domain: String
        get() = rawParser.javaClass.getMethod("getDomain").invoke(rawParser) as String

    @Deprecated("Too complex. Use getList with filter instead")
    override suspend fun getList(query: MangaSearchQuery): List<Manga> {
        return emptyList()
    }

    override suspend fun getList(offset: Int, order: SortOrder, filter: MangaListFilter): List<Manga> {
        val childSortOrderClass = childClassLoader.loadClass("org.koitharu.kotatsu.parsers.model.SortOrder")
        val childOrder = childSortOrderClass.getMethod("valueOf", String::class.java).invoke(null, order.name)

        val filterClass = childClassLoader.loadClass("org.koitharu.kotatsu.parsers.model.MangaListFilter")
        val emptySet = emptySet<Any>()
        val filterConstructor = filterClass.getConstructor(
            String::class.java,
            Set::class.java,
            Set::class.java,
            Locale::class.java,
            Locale::class.java,
            Set::class.java,
            Set::class.java,
            Set::class.java,
            Set::class.java,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
            String::class.java
        )
        // The "no year" marker differs between parsers versions, read the jar's own.
        val yearUnknown = try {
            childClassLoader.loadClass("org.koitharu.kotatsu.parsers.model.ConstantsKt")
                .getField("YEAR_UNKNOWN").getInt(null)
        } catch (_: Throwable) {
            0
        }
        val childFilter = filterConstructor.newInstance(
            filter.query,
            emptySet,
            emptySet,
            null,
            null,
            emptySet,
            emptySet,
            emptySet,
            emptySet,
            yearUnknown,
            yearUnknown,
            yearUnknown,
            null
        )

        val getListMethod = rawParser.javaClass.methods.first { m ->
            m.name == "getList" && m.parameterTypes.size == 4 && m.parameterTypes[0] == Int::class.javaPrimitiveType
        }

        val rawResult = invokeSuspendMethod(getListMethod, rawParser, offset, childOrder, childFilter) as List<*>
        return rawResult.map { mapChildMangaToParent(it!!) }
    }

    override suspend fun getDetails(manga: Manga): Manga {
        val childManga = mapParentMangaToChild(manga)
        val getDetailsMethod = rawParser.javaClass.methods.first { m ->
            m.name == "getDetails" && m.parameterTypes.size == 2
        }
        val rawResult = invokeSuspendMethod(getDetailsMethod, rawParser, childManga)
        return mapChildMangaToParent(rawResult!!)
    }

    override suspend fun getPages(chapter: MangaChapter): List<MangaPage> {
        val childChapter = mapParentChapterToChild(chapter)
        val getPagesMethod = rawParser.javaClass.methods.first { m ->
            m.name == "getPages" && m.parameterTypes.size == 2
        }
        val rawResult = invokeSuspendMethod(getPagesMethod, rawParser, childChapter) as List<*>
        return rawResult.map { mapChildPageToParent(it!!) }
    }

    override suspend fun getPageUrl(page: MangaPage): String {
        val childPage = mapParentPageToChild(page)
        val getPageUrlMethod = rawParser.javaClass.methods.first { m ->
            m.name == "getPageUrl" && m.parameterTypes.size == 2
        }
        return invokeSuspendMethod(getPageUrlMethod, rawParser, childPage) as String
    }

    override suspend fun getFilterOptions(): MangaListFilterOptions {
        return MangaListFilterOptions(availableTags = emptySet())
    }

    override suspend fun getFavicons(): Favicons {
        return Favicons.EMPTY
    }

    override fun onCreateConfig(keys: MutableCollection<ConfigKey<*>>) {}

    override suspend fun getRelatedManga(seed: Manga): List<Manga> {
        return emptyList()
    }

    override fun getRequestHeaders(): Headers {
        return try {
            val method = rawParser.javaClass.getMethod("getRequestHeaders")
            method.invoke(rawParser) as Headers
        } catch (e: Exception) {
            Headers.Builder().build()
        }
    }

    override suspend fun resolveLink(link: HttpUrl): Manga? {
        val getResolveLinkMethod = rawParser.javaClass.methods.firstOrNull { m ->
            m.name == "resolveLink" && m.parameterTypes.size == 2 && m.parameterTypes[0] == HttpUrl::class.java
        } ?: return null
        val rawResult = invokeSuspendMethod(getResolveLinkMethod, rawParser, link) ?: return null
        return mapChildMangaToParent(rawResult)
    }

    private fun getFieldValue(obj: Any?, fieldName: String): Any? {
        if (obj == null) return null
        return try {
            val field = obj.javaClass.getDeclaredField(fieldName)
            field.isAccessible = true
            field.get(obj)
        } catch (e: Exception) {
            val getterName = "get" + fieldName.replaceFirstChar { it.uppercase() }
            try {
                val method = obj.javaClass.getMethod(getterName)
                method.invoke(obj)
            } catch (ex: Exception) {
                null
            }
        }
    }

    private fun mapChildMangaToParent(childManga: Any): Manga {
        val id = getFieldValue(childManga, "id") as Long
        val title = getFieldValue(childManga, "title") as String
        val altTitles = (getFieldValue(childManga, "altTitles") as? Set<*>)?.map { it.toString() }?.toSet() ?: emptySet()
        val url = getFieldValue(childManga, "url") as String
        val publicUrl = getFieldValue(childManga, "publicUrl") as? String ?: ""
        val rating = (getFieldValue(childManga, "rating") as? Number)?.toFloat() ?: 0f

        val rawContentRating = getFieldValue(childManga, "contentRating")
        val contentRatingVal = if (rawContentRating != null) {
            try {
                val name = rawContentRating.javaClass.getMethod("name").invoke(rawContentRating) as String
                ContentRating.valueOf(name)
            } catch (e: Exception) {
                null
            }
        } else null

        val coverUrl = getFieldValue(childManga, "coverUrl") as? String

        val rawTags = (getFieldValue(childManga, "tags") as? Set<*>) ?: emptySet<Any>()
        val tagsVal = rawTags.mapNotNull { t ->
            val tId = getFieldValue(t, "key") as? String ?: getFieldValue(t, "id") as? String ?: return@mapNotNull null
            val tTitle = getFieldValue(t, "title") as? String ?: return@mapNotNull null
            MangaTag(title = tTitle, key = tId, source = this.source)
        }.toSet()

        val rawState = getFieldValue(childManga, "state")
        val stateVal = if (rawState != null) {
            try {
                val name = rawState.javaClass.getMethod("name").invoke(rawState) as String
                MangaState.valueOf(name)
            } catch (e: Exception) {
                null
            }
        } else null

        val authors = (getFieldValue(childManga, "authors") as? Set<*>)?.map { it.toString() }?.toSet() ?: emptySet()
        val largeCoverUrl = getFieldValue(childManga, "largeCoverUrl") as? String
        val description = getFieldValue(childManga, "description") as? String

        val rawChapters = getFieldValue(childManga, "chapters") as? List<*>
        val chaptersVal = rawChapters?.map { ch ->
            mapChildChapterToParent(ch!!)
        }

        return Manga(
            id = id,
            title = title,
            altTitles = altTitles,
            url = url,
            publicUrl = publicUrl,
            rating = rating,
            contentRating = contentRatingVal,
            coverUrl = coverUrl,
            tags = tagsVal,
            state = stateVal,
            authors = authors,
            largeCoverUrl = largeCoverUrl,
            description = description,
            chapters = chaptersVal,
            source = this.source
        )
    }

    private fun mapChildChapterToParent(childChapter: Any): MangaChapter {
        val id = getFieldValue(childChapter, "id") as Long
        val titleVal = getFieldValue(childChapter, "title") as? String
        val number = (getFieldValue(childChapter, "number") as? Number)?.toFloat() ?: 0f
        val volume = (getFieldValue(childChapter, "volume") as? Number)?.toInt() ?: 0
        val url = getFieldValue(childChapter, "url") as String
        val scanlator = getFieldValue(childChapter, "scanlator") as? String
        val uploadDate = (getFieldValue(childChapter, "uploadDate") as? Number)?.toLong() ?: 0L
        val branch = getFieldValue(childChapter, "branch") as? String

        return MangaChapter(
            id = id,
            title = titleVal,
            number = number,
            volume = volume,
            url = url,
            scanlator = scanlator,
            uploadDate = uploadDate,
            branch = branch,
            source = this.source
        )
    }

    private fun mapChildPageToParent(childPage: Any): MangaPage {
        val id = getFieldValue(childPage, "id") as Long
        val url = getFieldValue(childPage, "url") as String
        val previewUrl = getFieldValue(childPage, "preview") as? String ?: getFieldValue(childPage, "previewUrl") as? String

        return MangaPage(
            id = id,
            url = url,
            preview = previewUrl,
            source = this.source
        )
    }

    private fun mapParentMangaToChild(parentManga: Manga): Any {
        val mangaClass = childClassLoader.loadClass("org.koitharu.kotatsu.parsers.model.Manga")
        val contentRatingClass = childClassLoader.loadClass("org.koitharu.kotatsu.parsers.model.ContentRating")
        val mangaStateClass = childClassLoader.loadClass("org.koitharu.kotatsu.parsers.model.MangaState")
        val mangaTagClass = childClassLoader.loadClass("org.koitharu.kotatsu.parsers.model.MangaTag")
        val mangaSourceClass = childClassLoader.loadClass("org.koitharu.kotatsu.parsers.model.MangaSource")

        val contentRating = parentManga.contentRating
        val childContentRating = if (contentRating != null) {
            contentRatingClass.getMethod("valueOf", String::class.java).invoke(null, contentRating.name)
        } else null

        val state = parentManga.state
        val childState = if (state != null) {
            mangaStateClass.getMethod("valueOf", String::class.java).invoke(null, state.name)
        } else null

        val childSource = rawParser.javaClass.getMethod("getSource").invoke(rawParser)

        val childTags = parentManga.tags.map { t ->
            val constructor = mangaTagClass.constructors.firstOrNull { it.parameterTypes.size == 3 }
            if (constructor != null) {
                constructor.newInstance(t.title, t.key, childSource)
            } else {
                val constructor2 = mangaTagClass.getConstructor(String::class.java, String::class.java)
                constructor2.newInstance(t.title, t.key)
            }
        }.toSet()

        val childChapters = parentManga.chapters?.map { ch ->
            mapParentChapterToChild(ch)
        }

        val constructor = mangaClass.getConstructor(
            Long::class.javaPrimitiveType,
            String::class.java,
            Set::class.java,
            String::class.java,
            String::class.java,
            Float::class.javaPrimitiveType,
            contentRatingClass,
            String::class.java,
            Set::class.java,
            mangaStateClass,
            Set::class.java,
            String::class.java,
            String::class.java,
            List::class.java,
            mangaSourceClass
        )

        return constructor.newInstance(
            parentManga.id,
            parentManga.title,
            parentManga.altTitles,
            parentManga.url,
            parentManga.publicUrl,
            parentManga.rating,
            childContentRating,
            parentManga.coverUrl,
            childTags,
            childState,
            parentManga.authors,
            parentManga.largeCoverUrl,
            parentManga.description,
            childChapters,
            childSource
        )
    }

    private fun mapParentChapterToChild(parentChapter: MangaChapter): Any {
        val chapterClass = childClassLoader.loadClass("org.koitharu.kotatsu.parsers.model.MangaChapter")
        val mangaSourceClass = childClassLoader.loadClass("org.koitharu.kotatsu.parsers.model.MangaSource")
        val childSource = rawParser.javaClass.getMethod("getSource").invoke(rawParser)

        val constructor = chapterClass.getConstructor(
            Long::class.javaPrimitiveType,
            String::class.java,
            Float::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
            String::class.java,
            String::class.java,
            Long::class.javaPrimitiveType,
            String::class.java,
            mangaSourceClass
        )

        return constructor.newInstance(
            parentChapter.id,
            parentChapter.title,
            parentChapter.number,
            parentChapter.volume,
            parentChapter.url,
            parentChapter.scanlator,
            parentChapter.uploadDate,
            parentChapter.branch,
            childSource
        )
    }

    private fun mapParentPageToChild(parentPage: MangaPage): Any {
        val pageClass = childClassLoader.loadClass("org.koitharu.kotatsu.parsers.model.MangaPage")
        val mangaSourceClass = childClassLoader.loadClass("org.koitharu.kotatsu.parsers.model.MangaSource")
        val childSource = rawParser.javaClass.getMethod("getSource").invoke(rawParser)

        val constructor = pageClass.getConstructor(
            Long::class.javaPrimitiveType,
            String::class.java,
            String::class.java,
            mangaSourceClass
        )

        return constructor.newInstance(
            parentPage.id,
            parentPage.url,
            parentPage.preview,
            childSource
        )
    }

    private suspend fun invokeSuspendMethod(method: Method, target: Any, vararg args: Any?): Any? {
        return suspendCoroutineUninterceptedOrReturn { cont ->
            val newArgs = arrayOf(*args, cont)
            val result = method.invoke(target, *newArgs)
            if (result == COROUTINE_SUSPENDED) {
                COROUTINE_SUSPENDED
            } else {
                result
            }
        }
    }
}
