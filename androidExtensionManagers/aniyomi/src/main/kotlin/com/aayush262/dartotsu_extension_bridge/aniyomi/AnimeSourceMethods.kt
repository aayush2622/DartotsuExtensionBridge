package com.aayush262.dartotsu_extension_bridge.aniyomi

import eu.kanade.tachiyomi.PreferenceScreen
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.AnimeSource
import eu.kanade.tachiyomi.animesource.ConfigurableAnimeSource
import eu.kanade.tachiyomi.animesource.model.AnimeFilterList
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.Hoster
import eu.kanade.tachiyomi.animesource.model.Hoster.Companion.toHosterList
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource
import eu.kanade.tachiyomi.animesource.online.ParsedAnimeHttpSource
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import tachiyomi.domain.entries.anime.model.Anime
import tachiyomi.source.local.entries.anime.LocalAnimeSource
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import kotlin.collections.flatten

class AnimeSourceMethods(sourceID: String) : AniyomiSourceMethods {

    private val source: AnimeCatalogueSource

    init {
        val manager = Injekt.get<AniyomiExtensionManager>()

        val src = manager.installedAnimeExtensions.asSequence().flatMap { it.sources.asSequence() }.firstOrNull { it.id.toString() == sourceID }
            ?: throw IllegalArgumentException("Anime source with ID '$sourceID' not found.")

        source = src as? AnimeHttpSource ?: src as? AnimeCatalogueSource ?: throw IllegalArgumentException(
            "Source with ID '$sourceID' is not an AnimeHttpSource or AnimeCatalogueSource"
        )
    }


    override var baseUrl = (source as? AnimeHttpSource)?.baseUrl

    override suspend fun getPopular(page: Int): AnimesPage = source.getPopularAnime(page)

    override suspend fun getLatestUpdates(page: Int): AnimesPage = source.getLatestUpdates(page)


    override suspend fun getSearchResults(query: String, page: Int): AnimesPage = source.getSearchAnime(
        page = page, query = query, filters = AnimeFilterList()
    )

    override suspend fun getDetails(media: SAnime): SAnime = source.getAnimeDetails(media)
    override suspend fun getEpisodeList(media: SAnime): List<SEpisode> {
        runCatching {
            return source.getEpisodeList(media)
        }

        val seasons = runCatching { source.getSeasonList(media) }.getOrElse {
                throw UnsupportedOperationException(
                    "This source does not support fetching episodes."
                )
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
        val httpSource = source as? AnimeHttpSource ?: return emptyList()

        val directVideos = runCatching {
            httpSource.getVideoList(episode)
        }.getOrElse { emptyList() }

        val hasHosters = checkHasHosters(httpSource)

        val hosterVideos = if (hasHosters) {
            val hosters = runCatching {
                httpSource.getHosterList(episode)
            }.getOrElse { emptyList() }
            coroutineScope {
                hosters.map { hoster ->
                    async(Dispatchers.IO) {
                        val videos = when {
                            hoster.videoList != null -> hoster.videoList

                            else -> runCatching {
                                httpSource.getVideoList(hoster)
                            }.getOrElse { emptyList() }
                        }

                        videos.map { video ->
                            val resolved = resolveVideo(httpSource, video)

                            resolved.copy(
                                videoTitle = "${hoster.hosterName} - ${resolved.videoTitle}",
                                initialized = true
                            )
                        }
                    }
                }.awaitAll().flatten()
            }
        } else {
            emptyList()
        }

        return httpSource.run {
            (directVideos.map { resolveVideo(httpSource, it) } + hosterVideos)
                .distinctBy { it.videoUrl }
                .filter { it.videoUrl.isNotEmpty() && it.videoUrl != "null" }
                .sortVideos()
        }
    }

    override suspend fun getChapterList(media: SAnime): List<SEpisode> = throw UnsupportedOperationException("Chapters are not supported in anime sources.")

    override suspend fun getPageList(chapter: SChapter): List<Page> = throw UnsupportedOperationException("Pages are not supported in anime sources.")

    override fun setupPreferenceScreen(screen: PreferenceScreen) {
        if (source is ConfigurableAnimeSource) {
            source.setupPreferenceScreen(screen)
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

