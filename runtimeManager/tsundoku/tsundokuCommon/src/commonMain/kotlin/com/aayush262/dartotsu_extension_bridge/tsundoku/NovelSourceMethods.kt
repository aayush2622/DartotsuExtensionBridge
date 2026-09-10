package com.aayush262.dartotsu_extension_bridge.tsundoku



import android.content.SharedPreferences
import com.aayush262.dartotsu_extension_bridge.aniyomi.AniyomiSourceMethods
import com.aayush262.dartotsu_extension_bridge.aniyomi.NoPreferenceScreenException
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import eu.kanade.tachiyomi.PreferenceScreen
import eu.kanade.tachiyomi.animesource.model.AnimeUpdateStrategy
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.FetchType
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.ConfigurableSource
import eu.kanade.tachiyomi.source.NovelSource
import eu.kanade.tachiyomi.source.isNovelSource
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.model.UpdateStrategy
import eu.kanade.tachiyomi.source.online.HttpSource
import eu.kanade.tachiyomi.source.sourcePreferences
import kotlinx.serialization.json.JsonObject
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import java.util.regex.Matcher
import java.util.regex.Pattern

@Suppress("PrivatePropertyName")
class NovelSourceMethods(sourceID: String) : AniyomiSourceMethods {


    private val source: CatalogueSource

    init {
        val manager = Injekt.get<TsundokuExtensionManager>()

        val src = manager.installedNovelExtensions
            .asSequence()
            .flatMap { (ext, _) -> ext.sources.asSequence() }
            .firstOrNull { it.id.toString() == sourceID }
            ?: throw IllegalArgumentException(
                "Manga source with ID '$sourceID' not found."
            )

        source = src as? HttpSource
            ?: src as? CatalogueSource
                    ?: throw IllegalArgumentException(
                "Source with ID '$sourceID' is not an HttpSource or CatalogueSource"
            )
    }

    override var baseUrl = (source as? HttpSource)?.baseUrl

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

    override suspend fun getDetails(media: SAnime): Pair<SAnime, List<SEpisode>> {
        val data = source.getMangaUpdate(
            media.toSManga(),
            emptyList(),
            fetchDetails = true,
            fetchChapters = true
        )

        return data.manga.toSAnime() to data.chapters.map { it.toSEpisode() }
    }

    override suspend fun getPageList( chapter: SChapter): List<Page> {
        if (source.isNovelSource()) {
            return listOf(Page(0, chapter.url))
        }
        return (source).getPageList(chapter)
    }

    override suspend fun fetchPageText(page: Page): String {
        if (source.isNovelSource()) {
            return source.fetchPageText(page)
        }
        return super.fetchPageText(page)
    }
    override fun setupPreferenceScreen(screen: PreferenceScreen) {
        if (source is ConfigurableSource) {
            source.setupPreferenceScreen(screen)
        } else {
            throw NoPreferenceScreenException("This source does not support preferences.")
        }
    }


    override suspend fun getVideoList(episode: SEpisode): List<Video> {
        throw UnsupportedOperationException()
    }
    override fun getSourcePreferences(): SharedPreferences {
        if (source is ConfigurableSource) {
            return source.sourcePreferences()
        } else {
            throw NoPreferenceScreenException("This source does not support preferences.")
        }
    }
    private fun mangaPageToAnimePage(mangaPage: MangasPage): AnimesPage {
        return AnimesPage(
            mangaPage.mangas.map { it.toSAnime() },
            mangaPage.hasNextPage
        )
    }
    // Built through the SXxx.create() factories rather than anonymous `object :` bodies so that
    // adding a field to the source-api (as extensions-lib 17 / tachiyomix 1.7 did) doesn't break
    // this file.

    fun SChapter.toSEpisode(): SEpisode {
        val chapter = this
        return SEpisode.create().apply {
            url = chapter.url
            name = chapter.name
            date_upload = chapter.date_upload
            episode_number = findChapterNumber(chapter.name)
                ?: chapter.number?.toFloatOrNull()
                ?: -1f
            fillermark = false
            scanlator = chapter.scanlators.takeIf { it.isNotEmpty() }?.joinToString(", ")
            summary = chapter.note
            preview_url = null
            memo = chapter.memo
        }
    }

    fun SAnime.toSManga(): SManga {
        val anime = this
        return SManga.create().apply {
            url = anime.url
            title = anime.title
            artist = anime.artist
            author = anime.author
            description = anime.description
            genres = anime.getGenres() ?: emptyList()
            status = anime.status
            thumbnail_url = anime.thumbnail_url
            banner = anime.background_url
            update_strategy = UpdateStrategy.ALWAYS_UPDATE
            initialized = anime.initialized
            memo = anime.memo
        }
    }

    fun SManga.toSAnime(): SAnime {
        val manga = this

        return SAnime.create().apply {
            url = runCatching { manga.url }.getOrElse {
                Logger.log("Uninitialized URL for SManga: ${safeUrl(manga)}")
                "[UNINITIALIZED_URL]"
            }

            title = runCatching { manga.title }.getOrElse {
                Logger.log("Uninitialized title for SManga: ${safeTitle(manga)}")
                "[UNINITIALIZED_TITLE]"
            }

            artist = runCatching { manga.artist }.getOrNull()
            author = runCatching { manga.author }.getOrNull()
            description = runCatching { manga.description }.getOrNull()
            genre = runCatching { manga.genres.takeIf { g -> g.isNotEmpty() }?.joinToString(", ") }.getOrNull()
            status = runCatching { manga.status }.getOrDefault(SAnime.UNKNOWN)
            thumbnail_url = runCatching { manga.thumbnail_url }.getOrNull()
            background_url = runCatching { manga.banner }.getOrNull()
            update_strategy = AnimeUpdateStrategy.ALWAYS_UPDATE
            fetch_type = FetchType.Episodes
            season_number = 1.0
            initialized = runCatching { manga.initialized }.getOrDefault(false)
            memo = runCatching { manga.memo }.getOrDefault(JsonObject(emptyMap()))
        }
    }
    private fun safeTitle(manga: SManga): String =
        runCatching { manga.title }.getOrElse { "[UNINITIALIZED_TITLE]" }

    private fun safeUrl(manga: SManga): String =
        runCatching { manga.url }.getOrElse { "[UNINITIALIZED_URL]" }
    private val REGEX_ITEM = "[\\s:.\\-]*(\\d+\\.?\\d*)[\\s:.\\-]*"
    private val REGEX_PART_NUMBER = "(?<!part\\s)\\b(\\d+)\\b"
    private val REGEX_CHAPTER = "(chapter|chap|ch|c)${REGEX_ITEM}"
    fun findChapterNumber(text: String): Float? {
        val pattern: Pattern = Pattern.compile(REGEX_CHAPTER, Pattern.CASE_INSENSITIVE)
        val matcher: Matcher = pattern.matcher(text)

        return if (matcher.find()) {
            matcher.group(2)?.toFloat()
        } else {
            val failedChapterNumberPattern: Pattern =
                Pattern.compile(REGEX_PART_NUMBER, Pattern.CASE_INSENSITIVE)
            val failedChapterNumberMatcher: Matcher =
                failedChapterNumberPattern.matcher(text)
            if (failedChapterNumberMatcher.find()) {
                failedChapterNumberMatcher.group(1)?.toFloat()
            } else {
                text.toFloatOrNull()
            }
        }
    }

}