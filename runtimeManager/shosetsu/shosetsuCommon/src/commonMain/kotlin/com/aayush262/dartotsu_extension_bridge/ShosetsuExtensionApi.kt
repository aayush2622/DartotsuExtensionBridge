package com.aayush262.dartotsu_extension_bridge

import app.shosetsu.lib.Extension
import app.shosetsu.lib.Filter
import app.shosetsu.lib.Novel
import app.shosetsu.lib.PAGE_INDEX
import app.shosetsu.lib.QUERY_INDEX
import app.shosetsu.lib.ShosetsuSharedLib
import app.shosetsu.lib.exceptions.MissingExtensionLibrary
import app.shosetsu.lib.lua.LuaExtension
import app.shosetsu.lib.lua.ShosetsuLuaLib
import app.shosetsu.lib.lua.shosetsuGlobals
import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.aayush262.dartotsu_extension_bridge.network.Network
import com.google.gson.Gson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request
import org.luaj.vm2.LuaValue
import java.io.File
import java.util.concurrent.ConcurrentHashMap

expect object ShosetsuPlatformInit {
    fun initializeAndroid(context: Any)
    fun initializeDesktop(basePath: String, api: ExtensionBridgeApi)
}

class ShosetsuExtensionApi : ExtensionApi, ExtensionBridgeApi {

    override fun initializeAndroid(context: Any) {
        ShosetsuPlatformInit.initializeAndroid(context)
        setupLuaEngine()
    }

    override fun initializeDesktop(basePath: String) {
        ShosetsuPlatformInit.initializeDesktop(basePath, this)
        setupLuaEngine()
    }

    private fun setupLuaEngine() {
        ShosetsuSharedLib.httpClient = Network.newClient()
        ShosetsuSharedLib.logger = { name, log -> Logger.log("[$name] $log") }
        ShosetsuLuaLib.libLoader = ShosetsuExtensionManager::loadLibrary
    }

    override fun initClient(data: String) {
        Network.configure(data)
        ShosetsuSharedLib.httpClient = Network.newClient()
    }

    private val gson = Gson()

    private fun encode(data: Any?): String = gson.toJson(data)

    @Suppress("UNCHECKED_CAST")
    private fun decode(json: String): Map<String, Any?> = gson.fromJson(json, Map::class.java) as Map<String, Any?>

    override suspend fun getInstalledNovelExtensions(path: String?): String {
        path ?: return "[]"

        val result = withContext(Dispatchers.IO) {
            ShosetsuExtensionManager.scanInstalled(path).map { (id, ext) ->
                mapOf(
                    "id" to id,
                    "name" to ext.name,
                    "baseUrl" to ext.baseURL,
                    "lang" to ShosetsuExtensionManager.langOf(id),
                    "isNsfw" to false,
                    "iconUrl" to ext.imageURL,
                    "version" to ext.exMetaData.version.toString(),
                    "pkgName" to id,
                    "apkPath" to "",
                    "itemType" to 2,
                    "isShared" to false,
                )
            }
        }

        return encode(result)
    }

    override suspend fun getPopular(sourceId: String, isAnime: Boolean, page: Int): String =
        withContext(Dispatchers.IO) {
            val ext = ShosetsuExtensionManager.get(sourceId)
            val listing = ext.listings.firstOrNull()
                ?: return@withContext encode(mapOf("list" to emptyList<Any>(), "hasNextPage" to false))
            val novels = listing.getListing(mapOf(PAGE_INDEX to page))
            encode(
                mapOf(
                    "list" to novels.map { it.toListMap(ext) },
                    "hasNextPage" to (listing.isIncrementing && novels.isNotEmpty()),
                ),
            )
        }

    override suspend fun getLatestUpdates(sourceId: String, isAnime: Boolean, page: Int): String =
        withContext(Dispatchers.IO) {
            val ext = ShosetsuExtensionManager.get(sourceId)
            val listing = ext.listings.firstOrNull {
                val n = it.name.lowercase()
                "latest" in n || "new" in n || "update" in n
            } ?: ext.listings.firstOrNull()
                ?: return@withContext encode(mapOf("list" to emptyList<Any>(), "hasNextPage" to false))
            val novels = listing.getListing(mapOf(PAGE_INDEX to page))
            encode(
                mapOf(
                    "list" to novels.map { it.toListMap(ext) },
                    "hasNextPage" to (listing.isIncrementing && novels.isNotEmpty()),
                ),
            )
        }

    override suspend fun search(
        sourceId: String, isAnime: Boolean, query: String, page: Int, filters: String,
    ): String = withContext(Dispatchers.IO) {
        val ext = ShosetsuExtensionManager.get(sourceId)

        if (!ext.hasSearch) {
            return@withContext encode(mapOf("list" to emptyList<Any>(), "hasNextPage" to false))
        }

        val cachedFilters = ShosetsuExtensionManager.filtersOf(sourceId) ?: ext.searchFiltersModel.also {
            ShosetsuExtensionManager.cacheFilters(sourceId, it)
        }

        @Suppress("UNCHECKED_CAST")
        val incoming = (gson.fromJson(filters, List::class.java) as? List<Map<String, Any?>>) ?: emptyList()

        val data = mutableMapOf<Int, Any>(QUERY_INDEX to query, PAGE_INDEX to page)
        applyFilterStates(cachedFilters, incoming, data)

        val novels = ext.search(data)
        encode(
            mapOf(
                "list" to novels.map { it.toListMap(ext) },
                "hasNextPage" to (ext.isSearchIncrementing && novels.isNotEmpty()),
            ),
        )
    }

    override suspend fun getFilterList(sourceId: String, isAnime: Boolean): String =
        withContext(Dispatchers.IO) {
            val ext = ShosetsuExtensionManager.get(sourceId)
            val filters = ext.searchFiltersModel
            ShosetsuExtensionManager.cacheFilters(sourceId, filters)
            encode(filters.map { it.toSourceFilterJson() })
        }

    override suspend fun getDetail(sourceId: String, isAnime: Boolean, media: String): String =
        withContext(Dispatchers.IO) {
            val ext = ShosetsuExtensionManager.get(sourceId)
            val mediaMap = decode(media)
            val shortUrl = mediaMap["url"] as String
            val longUrl = ext.expandURL(shortUrl, Extension.KEY_NOVEL_URL)

            val novel = ext.parseNovel(longUrl, true)

            encode(
                mapOf(
                    "title" to novel.title,
                    "url" to shortUrl,
                    "cover" to novel.imageURL,
                    "description" to novel.description,
                    "author" to novel.authors.joinToString(", "),
                    "artist" to novel.artists.joinToString(", "),
                    "genre" to (novel.genres.toList() + novel.tags.toList()),
                    "status" to novel.status.key,
                    "episodes" to novel.chapters.map { it.toEpisodeMap(ext) },
                ),
            )
        }

    override suspend fun getNovelContent(sourceId: String, episode: String): String =
        withContext(Dispatchers.IO) {
            val ext = ShosetsuExtensionManager.get(sourceId)
            val epMap = decode(episode)
            val shortUrl = epMap["url"] as String
            val longUrl = ext.expandURL(shortUrl, Extension.KEY_CHAPTER_URL)

            val passage = ext.getPassage(longUrl)
            val text = String(passage, Charsets.UTF_8)

            encode(listOf(text))
        }

    override suspend fun getPreference(sourceId: String, isAnime: Boolean): String =
        withContext(Dispatchers.IO) {
            val ext = ShosetsuExtensionManager.get(sourceId)
            encode(ext.settingsModel.map { it.toSourcePreferenceJson() })
        }

    override suspend fun saveSourcePreference(sourceId: String, key: String, value: String?): Boolean {
        if (value == null) return false
        val ext = ShosetsuExtensionManager.get(sourceId)
        val id = key.toIntOrNull() ?: return false

        val payload = try {
            decode(value)
        } catch (_: Exception) {
            return false
        }

        return try {
            ext.updateSetting(id, payload["value"])
            true
        } catch (e: Exception) {
            Logger.log("Failed to update Shosetsu setting $key: ${e.message}", LogLevel.ERROR)
            false
        }
    }
}

private fun applyFilterStates(
    cached: Array<Filter<*>>,
    incoming: List<Map<String, Any?>>,
    out: MutableMap<Int, Any>,
) {
    for (i in cached.indices) {
        val filter = cached[i]
        val edited = incoming.getOrNull(i) ?: continue
        when (filter) {
            is Filter.Header, Filter.Separator -> Unit
            is Filter.Text -> (edited["textValue"] as? String)?.let { out[filter.id] = it }
            is Filter.Password -> (edited["textValue"] as? String)?.let { out[filter.id] = it }
            is Filter.Switch -> (edited["checkBoxValue"] as? Boolean)?.let { out[filter.id] = it }
            is Filter.Checkbox -> (edited["checkBoxValue"] as? Boolean)?.let { out[filter.id] = it }
            is Filter.TriState -> (edited["triState"] as? Double)?.let { out[filter.id] = it.toInt() }
            is Filter.Dropdown -> (edited["selectIndex"] as? Double)?.let { out[filter.id] = it.toInt() }
            is Filter.RadioGroup -> (edited["selectIndex"] as? Double)?.let { out[filter.id] = it.toInt() }
            is Filter.FList -> {
                @Suppress("UNCHECKED_CAST")
                val nested = edited["group"] as? List<Map<String, Any?>> ?: emptyList()
                applyFilterStates(filter.filters.toTypedArray(), nested, out)
            }
            is Filter.Group<*> -> {
                @Suppress("UNCHECKED_CAST")
                val nested = edited["group"] as? List<Map<String, Any?>> ?: emptyList()
                applyFilterStates(filter.filters.toTypedArray(), nested, out)
            }
        }
    }
}

private fun Filter<*>.toSourceFilterJson(): Map<String, Any?> = when (this) {
    is Filter.Header -> mapOf("type" to "header", "name" to name)
    is Filter.Separator -> mapOf("type" to "separator", "name" to "")
    is Filter.Text -> mapOf("type" to "text", "name" to name, "textValue" to state)
    is Filter.Password -> mapOf("type" to "text", "name" to name, "textValue" to state)
    is Filter.Switch -> mapOf("type" to "checkbox", "name" to name, "checkBoxValue" to state)
    is Filter.Checkbox -> mapOf("type" to "checkbox", "name" to name, "checkBoxValue" to state)
    is Filter.TriState -> mapOf("type" to "tri_state", "name" to name, "triState" to state)
    is Filter.Dropdown -> mapOf(
        "type" to "select", "name" to name, "selectIndex" to state, "selectOptions" to choices,
    )
    is Filter.RadioGroup -> mapOf(
        "type" to "select", "name" to name, "selectIndex" to state, "selectOptions" to choices,
    )
    is Filter.FList -> mapOf(
        "type" to "group", "name" to name, "group" to filters.map { it.toSourceFilterJson() },
    )
    is Filter.Group<*> -> mapOf(
        "type" to "group", "name" to name, "group" to filters.map { it.toSourceFilterJson() },
    )
}

private fun Filter<*>.toSourcePreferenceJson(): Map<String, Any?>? = when (this) {
    is Filter.Header, Filter.Separator -> null
    is Filter.Text -> mapOf("key" to id.toString(), "type" to "text", "title" to name, "value" to state)
    is Filter.Password -> mapOf("key" to id.toString(), "type" to "text", "title" to name, "value" to state)
    is Filter.Switch -> mapOf("key" to id.toString(), "type" to "switch", "title" to name, "value" to state)
    is Filter.Checkbox -> mapOf("key" to id.toString(), "type" to "checkbox", "title" to name, "value" to state)
    is Filter.TriState -> mapOf("key" to id.toString(), "type" to "checkbox", "title" to name, "value" to (state != 0))
    is Filter.Dropdown -> mapOf(
        "key" to id.toString(), "type" to "list", "title" to name,
        "entries" to choices, "entryValues" to choices.indices.map { it.toString() },
        "value" to state.toString(),
    )
    is Filter.RadioGroup -> mapOf(
        "key" to id.toString(), "type" to "list", "title" to name,
        "entries" to choices, "entryValues" to choices.indices.map { it.toString() },
        "value" to state.toString(),
    )
    is Filter.FList -> null
    is Filter.Group<*> -> null
}

private fun Novel.Info.toListMap(ext: Extension): Map<String, Any?> = mapOf(
    "title" to title,
    "url" to ext.shrinkURL(link, Extension.KEY_NOVEL_URL),
    "cover" to imageURL,
    "description" to description,
    "author" to authors.joinToString(", "),
    "artist" to artists.joinToString(", "),
    "genre" to (genres.toList() + tags.toList()),
)

private fun Novel.Chapter.toEpisodeMap(ext: Extension): Map<String, Any?> = mapOf(
    "name" to title,
    "url" to ext.shrinkURL(link, Extension.KEY_CHAPTER_URL),
    "date_upload" to release,
    "episode_number" to order,
    "scanlator" to null,
)

object ShosetsuExtensionManager {
    private val installed = ConcurrentHashMap<String, LuaExtension>()
    private val meta = ConcurrentHashMap<String, Pair<String, String>>() // sourceId -> (repoBase, lang)
    private val searchFilters = ConcurrentHashMap<String, Array<Filter<*>>>()
    private val libraryCache = ConcurrentHashMap<String, LuaValue>()
    private val constructLock = Any()

    @Volatile
    private var currentRepoBase: String = ""

    fun scanInstalled(path: String): List<Pair<String, LuaExtension>> {
        val dir = File(path)
        val files = dir.listFiles { f -> f.isFile && f.extension == "lua" } ?: emptyArray()
        val result = mutableListOf<Pair<String, LuaExtension>>()

        for (file in files) {
            try {
                val metaFile = File(file.parentFile, "${file.name}.meta.json")
                val repoBase: String
                val lang: String
                if (metaFile.exists()) {
                    val parsed = Gson().fromJson(metaFile.readText(), Map::class.java)
                    repoBase = (parsed["repo"] as? String)?.trimEnd('/') ?: ""
                    lang = parsed["lang"] as? String ?: ""
                } else {
                    repoBase = ""
                    lang = ""
                }

                val content = file.readText()
                val ext = synchronized(constructLock) {
                    currentRepoBase = repoBase
                    LuaExtension(content, file.name)
                }

                val sourceId = ext.exMetaData.id.toString()
                installed[sourceId] = ext
                meta[sourceId] = repoBase to lang
                result += sourceId to ext
            } catch (e: Throwable) {
                Logger.log("Failed to load Shosetsu script ${file.name}: ${e.message}", LogLevel.ERROR)
            }
        }

        return result
    }

    fun langOf(sourceId: String): String = meta[sourceId]?.second ?: ""

    fun cacheFilters(sourceId: String, filters: Array<Filter<*>>) {
        searchFilters[sourceId] = filters
    }

    fun filtersOf(sourceId: String): Array<Filter<*>>? = searchFilters[sourceId]

    fun get(sourceId: String): LuaExtension =
        installed[sourceId] ?: throw IllegalArgumentException("Shosetsu source with ID '$sourceId' not found.")

    /** [ShosetsuLuaLib.libLoader]: resolves `Require(name)` against the repo of the extension currently being constructed. */
    fun loadLibrary(name: String): LuaValue? {
        libraryCache[name]?.let { return it }

        val base = currentRepoBase
        if (base.isBlank()) return null

        return try {
            val url = "$base/lib/$name.lua"
            val content = ShosetsuSharedLib.httpClient.newCall(Request.Builder().url(url).build()).execute().use { res ->
                if (!res.isSuccessful) throw MissingExtensionLibrary(name)
                res.body.string()
            }
            val value = shosetsuGlobals().load(content, "lib($name)").call()
            libraryCache[name] = value
            value
        } catch (e: Throwable) {
            Logger.log("Failed to load Shosetsu library '$name': ${e.message}", LogLevel.ERROR)
            null
        }
    }
}
