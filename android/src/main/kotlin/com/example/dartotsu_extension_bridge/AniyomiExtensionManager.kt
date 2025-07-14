package com.example.dartotsu_extension_bridge

import android.content.Context
import eu.kanade.tachiyomi.extension.anime.model.AnimeExtension
import eu.kanade.tachiyomi.extension.anime.model.AnimeLoadResult
import eu.kanade.tachiyomi.extension.util.ExtensionLoader
import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.network.awaitSuccess
import eu.kanade.tachiyomi.network.parseAs
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import com.example.dartotsu_extension_bridge.models.ExtensionJsonObject
import com.example.dartotsu_extension_bridge.models.toAnimeExtensions
import com.example.dartotsu_extension_bridge.models.toMangaExtensions
import eu.kanade.tachiyomi.extension.manga.model.MangaExtension
import eu.kanade.tachiyomi.extension.manga.model.MangaLoadResult
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import uy.kohesive.injekt.injectLazy


class AniyomiExtensionManager(var context: Context) {
    lateinit var installedAnimeExtensions: List<AnimeExtension.Installed>
    lateinit var availableAnimeExtension: List<AnimeExtension.Available>
    lateinit var installedMangaExtension : List<MangaExtension.Installed>
    lateinit var availableMangaExtension: List<MangaExtension.Available>
    private val json: Json by injectLazy()

    fun fetchInstalledAnimeExtensions(): List<AnimeExtension.Installed>? {
        val sources = ExtensionLoader.loadAnimeExtensions(context)
        installedAnimeExtensions =
            sources.filterIsInstance<AnimeLoadResult.Success>().map { it.extension }
        return installedAnimeExtensions
    }

    fun fetchInstalledMangaExtensions(): List<MangaExtension.Installed>? {
        val sources = ExtensionLoader.loadMangaExtensions(context)
        installedMangaExtension =
            sources.filterIsInstance<MangaLoadResult.Success>().map { it.extension }
        return installedMangaExtension
    }

    suspend fun findAvailableAnimeExtensions(repos: List<String>): List<AnimeExtension.Available> {
        if (repos.isEmpty()) return emptyList()

        val client = Injekt.get<OkHttpClient>()

        val extensions = repos.mapNotNull { repo ->
            val indexUrl = if (repo.contains("index.min.json")) repo
            else "${repo.trimEnd('/')}/index.min.json"

            val response = try {
                client.newCall(GET(indexUrl)).awaitSuccess()
            } catch (e: Throwable) {
                e.printStackTrace()
                try {
                    val fallbackUrl = "${fallbackRepoUrl(repo)?.trimEnd('/')}/index.min.json"
                    client.newCall(GET(fallbackUrl)).awaitSuccess()
                } catch (e2: Throwable) {
                    e2.printStackTrace()
                    null
                }
            }

            response?.let {
                try {
                    with(json) {
                        it.parseAs<List<ExtensionJsonObject>>()
                            .toAnimeExtensions(repo)
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                    null
                }
            }
        }.flatten()

        return extensions.filter { it.pkgName.isNotEmpty() }
            .also { availableAnimeExtension = it }
    }

    suspend fun findAvailableMangaExtensions(repos: List<String>): List<MangaExtension.Available> {
        if (repos.isEmpty()) return emptyList()

        val client = Injekt.get<OkHttpClient>()

        val extensions = repos.mapNotNull { repo ->
            val indexUrl = if (repo.contains("index.min.json")) repo
            else "${repo.trimEnd('/')}/index.min.json"

            val response = try {
                client.newCall(GET(indexUrl)).awaitSuccess()
            } catch (e: Throwable) {
                e.printStackTrace()
                try {
                    val fallbackUrl = "${fallbackRepoUrl(repo)?.trimEnd('/')}/index.min.json"
                    client.newCall(GET(fallbackUrl)).awaitSuccess()
                } catch (e2: Throwable) {
                    e2.printStackTrace()
                    null
                }
            }

            response?.let {
                try {
                    with(json) {
                        it.parseAs<List<ExtensionJsonObject>>()
                            .toMangaExtensions(repo)
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                    null
                }
            }
        }.flatten()

        return extensions.filter { it.pkgName.isNotEmpty() }
            .also { availableMangaExtension = it }
    }

    fun registerNewExtension(extension: AnimeExtension.Installed) {
        installedAnimeExtensions += extension
    }

    fun unregisterExtension(extension: AnimeExtension.Installed) {
        installedAnimeExtensions =
            installedAnimeExtensions.filter { it.pkgName != extension.pkgName }
    }

    fun updateExtension(extension: AnimeExtension.Installed) {
        installedAnimeExtensions = installedAnimeExtensions.map {
            if (it.pkgName == extension.pkgName) extension else it
        }
    }

    private fun fallbackRepoUrl(repoUrl: String): String? {
        var fallbackRepoUrl = "https://gcore.jsdelivr.net/gh/"
        val strippedRepoUrl = repoUrl
            .removePrefix("https://")
            .removePrefix("http://")
            .removeSuffix("/")
            .removeSuffix("/index.min.json")
        val repoUrlParts = strippedRepoUrl.split("/")
        if (repoUrlParts.size < 3) {
            return null
        }
        val repoOwner = repoUrlParts[1]
        val repoName = repoUrlParts[2]
        fallbackRepoUrl += "$repoOwner/$repoName"
        val repoBranch = if (repoUrlParts.size > 3) {
            repoUrlParts[3]
        } else {
            "main"
        }
        fallbackRepoUrl += "@$repoBranch"
        return fallbackRepoUrl
    }
}