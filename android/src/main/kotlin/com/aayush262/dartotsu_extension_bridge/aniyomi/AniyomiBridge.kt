package com.aayush262.dartotsu_extension_bridge.aniyomi
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import android.content.Context
import android.util.Log
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Headers
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import java.io.UnsupportedEncodingException
import java.net.URLDecoder

class AniyomiBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        context // just to keep the context reference alive
        Log.d("AniyomiBridge", "Method called: ${call.method} with args: ${call.arguments}")
        when (call.method) {
            "getInstalledAnimeExtensions" -> getInstalledAnimeExtensions(call, result)
            "getInstalledMangaExtensions" -> getInstalledMangaExtensions(call, result)
            "fetchAnimeExtensions" -> fetchAnimeExtensions(call, result)
            "fetchMangaExtensions" -> fetchMangaExtensions(call, result)
            "getLatestUpdates" -> getLatestUpdates(call, result)
            "getPopular" -> getPopular(call, result)
            "getDetail" -> getDetail(call, result)
            "getVideoList" -> getVideoList(call, result)
            "getPageList" -> getPageList(call, result)
            "search" -> search(call, result)
            "installExtension" -> installExtension(call, result)
            "uninstallExtension" -> uninstallExtension(call, result)
            else -> result.notImplemented()
        }
    }
    
    private fun installExtension(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: return result.error(
            "INVALID_ARGS",
            "Arguments were null or invalid",
            null
        )
        
        val apkPath = args["apkPath"] as? String
        
        if (apkPath == null) {
            return result.error("INVALID_ARGS", "Missing apkPath", null)
        }
        
        try {
            val apkFile = File(apkPath)
            if (!apkFile.exists()) {
                return result.error("FILE_NOT_FOUND", "APK file not found at path: $apkPath", null)
            }
            
            val mainAppPackageName = context.packageName
            
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(
                    FileProvider.getUriForFile(
                        context, 
                        "$mainAppPackageName.fileprovider", 
                        apkFile
                    ),
                    "application/vnd.android.package-archive"
                )
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            e.printStackTrace()
            result.success(false)
        }
    }

    private fun uninstallExtension(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: return result.error(
            "INVALID_ARGS",
            "Arguments were null or invalid", 
            null
        )
        
        val packageName = args["packageName"] as? String
        
        if (packageName == null) {
            return result.error("INVALID_ARGS", "Missing packageName", null)
        }
        
        try {
            val packageManager = context.packageManager
            val isInstalled = try {
                packageManager.getPackageInfo(packageName, 0)
                true
            } catch (e: PackageManager.NameNotFoundException) {
                false
            }
            
            if (!isInstalled) {
                result.success(false)
                return
            }
            
            val intent = Intent(Intent.ACTION_DELETE).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            e.printStackTrace()
            result.success(false)
        }
    }

    private fun getInstalledAnimeExtensions(call: MethodCall, result: MethodChannel.Result) {
        val extensionManager = Injekt.get<AniyomiExtensionManager>()
        try {
            val installedExtensions = extensionManager.fetchInstalledAnimeExtensions()
                ?.map { ext ->
                    mapOf(
                        "id" to ext.pkgName,
                        "name" to ext.name,
                        "lang" to ext.lang,
                        "isNsfw" to ext.isNsfw,
                        "iconUrl" to ext.iconUrl,
                        "version" to ext.versionName,
                        "libVersion" to ext.libVersion,
                        "supportedLanguages" to ext.sources.map { it.lang },
                        "itemType" to 1,
                        "hasUpdate" to ext.hasUpdate,
                        "isObsolete" to ext.isObsolete,
                        "isUnofficial" to ext.isUnofficial,
                    )
                }
            result.success(installedExtensions)
            Log.d(
                "AniyomiBridge",
                "Method called: ${call.method} returned ${installedExtensions?.size ?: 0} extensions"
            )
        } catch (e: Exception) {
            e.printStackTrace()
            result.error("ERROR", "Failed to get installed extensions: ${e.message}", null)
        }
    }

    private fun getInstalledMangaExtensions(call: MethodCall, result: MethodChannel.Result) {
        val extensionManager = Injekt.get<AniyomiExtensionManager>()
        try {
            val installedExtensions = extensionManager.fetchInstalledMangaExtensions()
                ?.map { ext ->
                    mapOf(
                        "id" to ext.pkgName,
                        "name" to ext.name,
                        "lang" to ext.lang,
                        "isNsfw" to ext.isNsfw,
                        "iconUrl" to ext.iconUrl,
                        "version" to ext.versionName,
                        "libVersion" to ext.libVersion,
                        "supportedLanguages" to ext.sources.map { it.lang },
                        "itemType" to 0,
                        "hasUpdate" to ext.hasUpdate,
                        "isObsolete" to ext.isObsolete,
                        "isUnofficial" to ext.isUnofficial,
                    )
                }
            result.success(installedExtensions)
            Log.d(
                "AniyomiBridge",
                "Method called: ${call.method} returned ${installedExtensions?.size ?: 0} extensions"
            )
        } catch (e: Exception) {
            e.printStackTrace()
            result.error("ERROR", "Failed to get installed extensions: ${e.message}", null)
        }
    }
    

    private fun fetchAnimeExtensions(call: MethodCall, result: MethodChannel.Result) {
        val extensionManager = Injekt.get<AniyomiExtensionManager>()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val args = call.arguments as? List<*>
                val repos = args?.filterIsInstance<String>() ?: emptyList()
                val availableExtensions = extensionManager.findAvailableAnimeExtensions(repos)

                val mapped = availableExtensions.map { ext ->
                    mapOf(
                        "name" to ext.name,
                        "id" to ext.pkgName,
                        "versionName" to ext.versionName,
                        "libVersion" to ext.libVersion,
                        "supportedLanguages" to ext.sources.map { it.lang },
                        "lang" to ext.lang,
                        "isNsfw" to ext.isNsfw,
                        "apkName" to ext.apkName,
                        "iconUrl" to ext.iconUrl,
                        "itemType" to 1,
                    )
                }
                withContext(Dispatchers.Main) {
                    result.success(mapped)
                    Log.d("AniyomiBridge", "Method called: ${call.method} returned $mapped")
                }
            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    result.error(
                        "ERROR",
                        "Failed to fetch available extensions: ${e.message}",
                        null
                    )
                }
            }
        }
    }

    private fun fetchMangaExtensions(call: MethodCall, result: MethodChannel.Result) {
        val extensionManager = Injekt.get<AniyomiExtensionManager>()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val args = call.arguments as? List<*>
                val repos = args?.filterIsInstance<String>() ?: emptyList()
                val availableExtensions = extensionManager.findAvailableMangaExtensions(repos)

                val mapped = availableExtensions.map { ext ->
                    mapOf(
                        "name" to ext.name,
                        "id" to ext.pkgName,
                        "versionName" to ext.versionName,
                        "libVersion" to ext.libVersion,
                        "supportedLanguages" to ext.sources.map { it.lang },
                        "lang" to ext.lang,
                        "apkName" to ext.apkName,
                        "isNsfw" to ext.isNsfw,
                        "iconUrl" to ext.iconUrl,
                        "itemType" to 0,
                    )
                }
                Log.d("AniyomiBridge", "Fetched ${mapped.size} manga extensions")
                withContext(Dispatchers.Main) {
                    result.success(mapped)
                    Log.d("AniyomiBridge", "Method called: ${call.method} returned $mapped")
                }
            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    result.error(
                        "ERROR",
                        "Failed to fetch available extensions: ${e.message}",
                        null
                    )
                }
            }
        }
    }

    private fun getDetail(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: return result.error(
            "INVALID_ARGS",
            "Arguments were null or invalid",
            null
        )

        val sourceId = args["sourceId"] as? String
        val isAnime = args["isAnime"] as? Boolean
        val animeMap = args["media"] as? Map<*, *>

        if (sourceId == null || isAnime == null || animeMap == null) {
            return result.error("INVALID_ARGS", "Missing required parameters", null)
        }

        val anime = SAnime.create().apply {
            title = animeMap["title"] as? String ?: ""
            url = animeMap["url"] as? String ?: return result.error(
                "EMPTY_URL",
                "Url cant be empty",
                null
            )
            thumbnail_url = animeMap["thumbnail_url"] as? String
            description = animeMap["description"] as? String
            artist = animeMap["artist"] as? String
            author = animeMap["author"] as? String
            genre = animeMap["genre"] as? String
        }
        val media = if (isAnime) AnimeSourceMethods(sourceId) else MangaSourceMethods(sourceId)

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val res = media.getDetails(anime)
                val eps = if (isAnime) media.getEpisodeList(anime) else media.getChapterList(anime)
                val resultMap = mapOf(
                    "title" to anime.title,
                    "url" to anime.url,
                    "cover" to anime.thumbnail_url,
                    "artist" to res.artist,
                    "author" to res.author,
                    "description" to res.description,
                    "genre" to res.getGenres(),
                    "status" to res.status,
                    "episodes" to eps.map {
                        mapOf(
                            "name" to it.name,
                            "url" to it.url,
                            "date_upload" to it.date_upload.toString(),
                            "episode_number" to it.episode_number.toString(),
                            "scanlator" to it.scanlator
                        )
                    }
                )
                withContext(Dispatchers.Main) {
                    result.success(resultMap)
                    Log.d("AniyomiBridge", "Method called: ${call.method} returned $resultMap")
                }
            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    result.error("ERROR", "Failed to get details: ${e.message}", null)
                }
            }
        }
    }

    private fun getLatestUpdates(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: return result.error(
            "INVALID_ARGS",
            "Arguments were null or invalid",
            null
        )

        val sourceId = args["sourceId"] as? String
        val isAnime = args["isAnime"] as? Boolean
        val page = args["page"] as? Int

        if (sourceId == null || isAnime == null || page == null) {
            return result.error("INVALID_ARGS", "Missing required parameters", null)
        }

        val media = if (isAnime) AnimeSourceMethods(sourceId) else MangaSourceMethods(sourceId)

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val res = media.getLatestUpdates(page)
                val resultMap = mapOf(
                    "list" to res.animes.map {
                        mapOf(
                            "title" to it.title,
                            "url" to it.url,
                            "cover" to it.thumbnail_url,
                            "artist" to it.artist,
                            "author" to it.author,
                            "description" to it.description,
                            "genre" to it.getGenres(),
                            "status" to it.status,
                        )
                    },
                    "hasNextPage" to res.hasNextPage
                )
                withContext(Dispatchers.Main) {
                    result.success(resultMap)
                    Log.d("AniyomiBridge", "Method called: ${call.method} returned $resultMap")
                }
            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    result.error("ERROR", "Failed to get latest updates: ${e.message}", null)
                }
            }
        }
    }

    private fun getPopular(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: return result.error(
            "INVALID_ARGS",
            "Arguments were null or invalid",
            null
        )

        val sourceId = args["sourceId"] as? String
        val isAnime = args["isAnime"] as? Boolean
        val page = args["page"] as? Int

        if (sourceId == null || isAnime == null || page == null) {
            return result.error("INVALID_ARGS", "Missing required parameters", null)
        }

        val media = if (isAnime) AnimeSourceMethods(sourceId) else MangaSourceMethods(sourceId)

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val res = media.getPopular(page)
                val resultMap = mapOf(
                    "list" to res.animes.map {
                        mapOf(
                            "title" to it.title,
                            "url" to it.url,
                            "cover" to it.thumbnail_url,
                            "artist" to it.artist,
                            "author" to it.author,
                            "description" to it.description,
                            "genre" to it.getGenres(),
                            "status" to it.status,
                        )
                    },
                    "hasNextPage" to res.hasNextPage
                )
                withContext(Dispatchers.Main) {
                    result.success(resultMap)
                    Log.d("AniyomiBridge", "Method called: ${call.method} returned $resultMap")
                }
            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    result.error("ERROR", "Failed to get popular: ${e.message}", null)
                }
            }
        }
    }

    private fun getVideoList(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: return result.error(
            "INVALID_ARGS",
            "Arguments were null or invalid",
            null
        )

        val sourceId = args["sourceId"] as? String
        val isAnime = args["isAnime"] as? Boolean
        val mediaUrl = args["episode"] as? Map<*, *>

        if (sourceId == null || isAnime == null || mediaUrl == null) {
            return result.error("INVALID_ARGS", "Missing required parameters", null)
        }
        val episode = SEpisode.create().apply {
            name = mediaUrl["name"] as? String ?: ""
            url = mediaUrl["url"] as? String ?: return result.error(
                "EMPTY_URL",
                "Url cant be empty",
                null
            )
            date_upload = (mediaUrl["date_upload"] as? Long)?.takeIf { it > 0 } ?: 0L
            episode_number = (mediaUrl["episode_number"] as? Double)?.toFloat() ?: 0f
            scanlator = mediaUrl["scanlator"] as? String
        }
        val media = if (isAnime) AnimeSourceMethods(sourceId) else MangaSourceMethods(sourceId)
        fun Headers.toMap(): Map<String, String> =
            names().associateWith { name -> this[name] ?: "" }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val res = media.getVideoList(episode)
                val resultList = res.map { video ->
                    mapOf(
                        "title" to video.videoTitle,
                        "url" to video.videoUrl,
                        "quality" to video.resolution,
                        "headers" to video.headers?.toMap(),
                        "subtitles" to video.subtitleTracks.map { track ->
                            mapOf(
                                "file" to track.url,
                                "label" to track.lang
                            )
                        },
                        "audios" to video.audioTracks.map { track ->
                            mapOf(
                                "file" to track.url,
                                "label" to track.lang
                            )
                        },
                    )
                }
                withContext(Dispatchers.Main) {
                    result.success(resultList)
                    Log.d("AniyomiBridge", "Method called: ${call.method} returned $resultList")

                }
            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    result.error("ERROR", "Failed to get video list: ${e.message}", null)
                }
            }
        }
    }

    private fun search(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: return result.error(
            "INVALID_ARGS",
            "Arguments were null or invalid",
            null
        )
        val sourceId = args["sourceId"] as? String
        val isAnime = args["isAnime"] as? Boolean
        val query = args["query"] as? String
        val page = args["page"] as? Int
        if (sourceId == null || isAnime == null || query == null || page == null) {
            return result.error("INVALID_ARGS", "Missing required parameters", null)
        }
        val media = if (isAnime) AnimeSourceMethods(sourceId) else MangaSourceMethods(sourceId)

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val res = media.getSearchResults(query, page)
                val resultMap = mapOf(
                    "list" to res.animes.map {
                        mapOf(
                            "title" to it.title,
                            "url" to it.url,
                            "cover" to it.thumbnail_url,
                            "artist" to it.artist,
                            "author" to it.author,
                            "description" to it.description,
                            "genre" to it.getGenres(),
                            "status" to it.status,
                        )
                    },
                    "hasNextPage" to res.hasNextPage
                )
                withContext(Dispatchers.Main) {
                    result.success(resultMap)
                    Log.d("AniyomiBridge", "Method called: ${call.method} returned $resultMap")
                }
            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    result.error("ERROR", "Failed to get video list: ${e.message}", null)
                }
            }
        }

    }

    private fun getPageList(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: return result.error(
            "INVALID_ARGS",
            "Arguments were null or invalid",
            null
        )

        val sourceId = args["sourceId"] as? String
        val isAnime = args["isAnime"] as? Boolean
        val mediaUrl = args["episode"] as? Map<*, *>

        if (sourceId == null || isAnime == null || mediaUrl == null) {
            return result.error("INVALID_ARGS", "Missing required parameters", null)
        }
        val episode = SChapter.create().apply {
            name = mediaUrl["name"] as? String ?: ""
            url = mediaUrl["url"] as? String ?: return result.error(
                "EMPTY_URL",
                "Url cant be empty",
                null
            )
            date_upload = (mediaUrl["date_upload"] as? Long)?.takeIf { it > 0 } ?: 0L
            chapter_number = (mediaUrl["episode_number"] as? Double)?.toFloat() ?: 0f
            scanlator = mediaUrl["scanlator"] as? String
        }

        val media = if (isAnime) AnimeSourceMethods(sourceId) else MangaSourceMethods(sourceId)
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val res = media.getPageList(episode)
                val resultList = res.map { chapter ->
                    val (url, headers) = pageToUrlAndHeaders(chapter)
                    mapOf(
                        "url" to url,
                        "headers" to headers,
                    )
                }
                withContext(Dispatchers.Main) {
                    result.success(resultList)
                    Log.d("AniyomiBridge", "Method called: ${call.method} returned $resultList")
                }
            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    result.error("ERROR", "Failed to get video list: ${e.message}", null)
                }
            }
        }
    }

    fun pageToUrlAndHeaders(page: Page): Pair<String, Map<String, String>> {
        var headersMap = emptyMap<String, String>()
        var url = ""

        page.imageUrl?.let {
            url = it
            val splitUrl = it.split("&")
            headersMap = splitUrl.mapNotNull { part ->
                val idx = part.indexOf("=")
                if (idx != -1) {
                    try {
                        val key = URLDecoder.decode(part.substring(0, idx), "UTF-8")
                        val value = URLDecoder.decode(part.substring(idx + 1), "UTF-8")
                        Pair(key, value)
                    } catch (e: UnsupportedEncodingException) {
                        Log.e("AniyomiBridge", "Error decoding URL part: $part", e)
                        null
                    }
                } else {
                    null
                }
            }.toMap()
        }
        return Pair(url, headersMap)
    }
}