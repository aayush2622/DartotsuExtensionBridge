package com.aayush262.dartotsu_extension_bridge.aniyomi

import android.util.Log
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.model.UpdateStrategy
import eu.kanade.tachiyomi.source.online.HttpSource
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get

class MangaSourceMethods(sourceID: String, langIndex: Int = 0) : AniyomiSourceMethods {

    private val source: CatalogueSource

    init {
        val manager = Injekt.get<AniyomiExtensionManager>()
        val extension = manager.installedMangaExtensions
            .find { it.pkgName == sourceID }
            ?: throw IllegalArgumentException("Manga source with ID '$sourceID' not found.")

        val src = extension.sources.getOrNull(langIndex) ?: extension.sources.firstOrNull()
        source = src as? HttpSource ?: src as? CatalogueSource
                ?: throw IllegalArgumentException("Source with ID '$sourceID' is not an HttpSource or CatalogueSource")
    }

    override suspend fun getPopular(page: Int): AnimesPage {
        return mangaPageToAnimePage(source.getPopularManga(page))
    }

    override suspend fun getLatestUpdates(page: Int): AnimesPage {
        return mangaPageToAnimePage(source.getLatestUpdates(page))
    }

    override suspend fun getSearchResults(query: String, page: Int): AnimesPage {
        return mangaPageToAnimePage(
            source.getSearchManga(
                page = page,
                query = query,
                filters = source.getFilterList()
            )
        )
    }

    override suspend fun getDetails(media: SAnime): SAnime {
        return source.getMangaDetails(media.toSManga()).toSAnime()
    }

    override suspend fun getChapterList(media: SAnime): List<SEpisode> {
        return source.getChapterList(media.toSManga()).map { it.toSEpisode() }
    }

    override suspend fun getPageList( chapter: SChapter): List<Page> {
       return (source).getPageList(chapter)
    }

    override suspend fun getEpisodeList(media: SAnime): List<SEpisode> {
        throw UnsupportedOperationException()
    }

    override suspend fun getVideoList(episode: SEpisode): List<Video> {
        throw UnsupportedOperationException()
    }

    private fun mangaPageToAnimePage(mangaPage: MangasPage): AnimesPage {
        return AnimesPage(
            mangaPage.mangas.map { it.toSAnime() },
            mangaPage.hasNextPage
        )
    }
    fun SChapter.toSEpisode(): SEpisode {
        val chapter = this
        return object : SEpisode {
            override var url: String = chapter.url
            override var name: String = chapter.name
            override var date_upload: Long = chapter.date_upload
            override var episode_number: Float = chapter.chapter_number
            override var scanlator: String? = chapter.scanlator
        }
    }

    fun SAnime.toSManga(): SManga {
        val anime = this
        return object : SManga {
            override var url: String = anime.url
            override var title: String = anime.title
            override var artist: String? = anime.artist
            override var author: String? = anime.author
            override var description: String? = anime.description
            override var genre: String? = anime.genre
            override var status: Int = anime.status
            override var thumbnail_url: String? = anime.thumbnail_url
            override var update_strategy: UpdateStrategy = anime.update_strategy
            override var initialized: Boolean = anime.initialized
        }
    }

    fun SManga.toSAnime(): SAnime {
        val manga = this

        return object : SAnime {
            override var url: String = try {
                manga.url
            } catch (e: UninitializedPropertyAccessException) {
                Log.d("AniyomiExtensionBridge", "Uninitialized URL for SManga: ${manga.title}")
                "[UNINITIALIZED_URL]"
            }

            override var title: String = try {
                manga.title
            } catch (e: UninitializedPropertyAccessException) {
                Log.d("AniyomiExtensionBridge", "Uninitialized title for SManga: ${manga.url}")
                "[UNINITIALIZED_TITLE]"
            }

            override var artist: String? = manga.artist
            override var author: String? = manga.author
            override var description: String? = manga.description
            override var genre: String? = manga.genre
            override var status: Int = manga.status
            override var thumbnail_url: String? = manga.thumbnail_url
            override var update_strategy: UpdateStrategy = manga.update_strategy
            override var initialized: Boolean = manga.initialized
        }
    }


}