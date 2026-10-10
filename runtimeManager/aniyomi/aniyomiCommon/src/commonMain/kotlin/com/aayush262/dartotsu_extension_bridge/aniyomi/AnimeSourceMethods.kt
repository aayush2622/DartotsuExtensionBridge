package com.aayush262.dartotsu_extension_bridge.aniyomi

import kotlin.coroutines.cancellation.CancellationException
import android.content.SharedPreferences
import eu.kanade.tachiyomi.PreferenceScreen
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.AnimeSource
import eu.kanade.tachiyomi.animesource.ConfigurableAnimeSource
import eu.kanade.tachiyomi.animesource.model.AnimeFilterList
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.Hoster.Companion.NO_HOSTER_LIST
import eu.kanade.tachiyomi.animesource.model.HttpServer
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource
import eu.kanade.tachiyomi.animesource.online.ParsedAnimeHttpSource
import eu.kanade.tachiyomi.animesource.sourcePreferences
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import java.util.concurrent.ConcurrentHashMap
import kotlin.collections.flatten

class AnimeSourceMethods(private val sourceId: String) : AniyomiSourceMethods {

    private val source: AnimeCatalogueSource

    init {
        val manager = Injekt.get<AniyomiExtensionManager>()

        val src = manager.installedAnimeExtensions
            .asSequence()
            .flatMap { it.key.sources.asSequence() }
            .firstOrNull { it.id.toString() == sourceId }
            ?: throw IllegalArgumentException(
                "Anime source with ID '$sourceId' not found."
            )

        source = src as? AnimeHttpSource
            ?: src as? AnimeCatalogueSource
                    ?: throw IllegalArgumentException(
                "Source with ID '$sourceId' is not an AnimeHttpSource or AnimeCatalogueSource"
            )
    }


    override var baseUrl = (source as? AnimeHttpSource)?.baseUrl

    override suspend fun getPopular(page: Int): AnimesPage = source.getPopularAnime(page)

    override suspend fun getLatestUpdates(page: Int): AnimesPage = source.getLatestUpdates(page)

    override suspend fun getSearchResults(query: String, page: Int): AnimesPage = source.getSearchAnime(
        page = page, query = query, filters = source.getFilterList()
    )

    override suspend fun getDetails(media: SAnime): Pair<SAnime, List<SEpisode>> = source.getAnimeDetails(media) to getEpisodeList(media)


    suspend fun getEpisodeList(media: SAnime): List<SEpisode> {
        val episodeError = try {
            return (source as? AnimeHttpSource? ?: source).getEpisodeList(media)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            e
        }

        val seasons = try {
            source.getSeasonList(media)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            throw episodeError
        }

        val episodes = mutableListOf<SEpisode>()

        seasons.forEachIndexed { _, season ->
            val seasonEpisodes = runCatching {
                source.getEpisodeList(season)
            }.getOrNull() ?: emptyList()

            seasonEpisodes.forEach { ep ->
                ep.name = "${season.title}: ${ep.name}"
            }

            episodes += seasonEpisodes
        }

        return episodes.distinctBy { it.url }.sortedByDescending { it.episode_number }
    }

    override suspend fun getVideoList(episode: SEpisode): List<Video> {
        if (source !is AnimeHttpSource) return emptyList()
        val hasHosters = checkHasHosters(source)

        val directVideos = if (!hasHosters) {
            runCatching {
                source.getVideoList(episode)
            }.getOrElse { emptyList() }
        } else {
            emptyList()
        }

        val hosterVideos = if (hasHosters) {
            val hosters = runCatching {
                source.getHosterList(episode)
            }.getOrElse { emptyList() }

            coroutineScope {
                hosters.map { hoster ->
                    async(Dispatchers.IO) {

                        val videos = when {
                            !hoster.videoList.isNullOrEmpty() -> hoster.videoList
                            else -> runCatching {
                                source.getVideoList(hoster)
                            }.getOrElse { emptyList() }
                        }

                        videos.map { video ->
                            val resolved = resolveVideo(source, video)

                            val title = if (
                                hoster.hosterName.isBlank() ||
                                hoster.hosterName == NO_HOSTER_LIST
                            ) {
                                resolved.videoTitle
                            } else {
                                "${hoster.hosterName} - ${resolved.videoTitle}"
                            }

                            resolved.copy(
                                videoTitle = title,
                                initialized = true
                            )
                        }
                    }
                }.awaitAll().flatten()
            }
        } else {
            emptyList()
        }

        val resolvedDirect = coroutineScope {
            directVideos.map {
                async(Dispatchers.IO) {
                    resolveVideo(source, it)
                }
            }.awaitAll()
        }

        val videos = source.run {
            (resolvedDirect + hosterVideos)
                .distinctBy { it.videoUrl }
                .filter { it.videoUrl.isNotEmpty() && it.videoUrl != "null" }
                .sortVideos()
        }

        return applyHttpServers(videos)
    }

    /**
     * extensions-lib 17: a source can ask the app to run a local proxy server
     * for a video instead of returning a directly playable url (e.g. to inject
     * auth headers a player can't set itself) - [Video.usesHttpServer] is
     * `true` for such a video, and [AnimeHttpSource.createHttpServer] builds
     * the server that knows how to serve it. Legacy sources never produce a
     * video where [Video.usesHttpServer] is true, so this is a no-op for them.
     *
     * There's no separate "user picked this video to play" call in this
     * bridge's API - the whole list returned by [getVideoList] is handed to
     * Dart at once - so any server-backed video in the list gets its server
     * started eagerly here rather than lazily at playback time. A fresh
     * [getVideoList] call for this source (a new episode, or a refresh)
     * replaces the previous batch, so old servers are stopped first.
     */
    private fun applyHttpServers(videos: List<Video>): List<Video> {
        val httpSource = source as? AnimeHttpSource ?: return videos
        if (videos.none { it.usesHttpServer() }) return videos

        stopHttpServers(sourceId)
        val started = mutableListOf<HttpServer>()

        val result = videos.map { video ->
            if (!video.usesHttpServer()) return@map video

            val server = runCatching { httpSource.createHttpServer() }.getOrNull()
                ?: return@map video

            server.start()
            if (!server.isRunning()) return@map video

            started += server
            video.copyHttpServer(server.listeningPort)
        }

        if (started.isNotEmpty()) activeHttpServers[sourceId] = started
        return result
    }

    companion object {
        // Keyed by source id so the next getVideoList() call for the same
        // source can stop whatever servers a previous call started.
        private val activeHttpServers = ConcurrentHashMap<String, List<HttpServer>>()

        private fun stopHttpServers(sourceId: String) {
            activeHttpServers.remove(sourceId)?.forEach { server ->
                runCatching { if (server.isRunning()) server.stop() }
            }
        }
    }


    override suspend fun getPageList(chapter: SChapter): List<Page> = throw UnsupportedOperationException("Pages are not supported in anime sources.")

    override fun setupPreferenceScreen(screen: PreferenceScreen) {
        if (source is ConfigurableAnimeSource) {
            source.setupPreferenceScreen(screen)
        } else {
            throw NoPreferenceScreenException("This source does not support preferences.")
        }
    }

    override fun getSourcePreferences(): SharedPreferences {
        if (source is ConfigurableAnimeSource) {
            return source.sourcePreferences()
        } else {
            throw NoPreferenceScreenException("This source does not support preferences.")
        }
    }

    private fun checkHasHosters(source: AnimeHttpSource): Boolean {
        var current: Class<in AnimeHttpSource> = source.javaClass

        while (true) {
            if (current == ParsedAnimeHttpSource::class.java ||
                current == AnimeHttpSource::class.java ||
                current == AnimeSource::class.java
            ) {
                return false
            }

            if (current.declaredMethods.any {
                    it.name in listOf(
                        "getHosterList",
                        "hosterListRequest",
                        "hosterListParse"
                    )
                }
            ) {
                return true
            }

            current = current.superclass ?: return false
        }
    }

    private suspend fun resolveVideo(
        source: AnimeHttpSource,
        video: Video
    ): Video {
        if (video.initialized && video.videoUrl.isNotEmpty() && video.videoUrl != "null") {
            return video
        }

        val resolved = runCatching {
            source.resolveVideo(video)
        }.getOrNull()

        if (resolved != null) return resolved

        if (video.videoUrl == "null" || video.videoUrl.isEmpty()) {
            val newUrl = runCatching {
                source.getVideoUrl(video)
            }.getOrNull()

            return video.copy(videoUrl = newUrl ?: video.videoUrl)
        }

        return video
    }
}

class NoPreferenceScreenException(message: String) : Exception(message)

