package kuchihige.source

import eu.kanade.tachiyomi.source.NovelSource
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.online.HttpSource
import okhttp3.Request
import okhttp3.Response
import rx.Observable

abstract class NovelHttpSource :
    HttpSource(),
    NovelSource {
    typealias NovelsPage = MangasPage
    typealias SNovel = SManga

    override suspend fun fetchPageText(page: Page): String = throw UnsupportedOperationException("fetchPageText must be overridden")

    override fun imageUrlParse(response: Response): String {
        TODO("Not yet implemented")
    }

    open fun getNovelUrl(novel: SNovel): String = super.getMangaUrl(novel)

    final override fun getMangaUrl(manga: SManga): String = getNovelUrl(manga)

    protected abstract fun novelDetailsParse(response: Response): SNovel

    final override fun mangaDetailsParse(response: Response): SManga = novelDetailsParse(response)

    open fun novelDetailsRequest(novel: SNovel): Request = super.mangaDetailsRequest(novel)

    final override fun mangaDetailsRequest(manga: SManga): Request = novelDetailsRequest(manga)

    open fun fetchNovelDetails(novel: SNovel): Observable<SNovel> = super.fetchMangaDetails(novel)

    final override fun fetchMangaDetails(manga: SManga): Observable<SManga> = fetchNovelDetails(manga)

    protected abstract fun popularNovelsParse(response: Response): NovelsPage

    final override fun popularMangaParse(response: Response): NovelsPage = popularNovelsParse(response)

    protected abstract fun popularNovelsRequest(page: Int): Request

    final override fun popularMangaRequest(page: Int): Request = popularNovelsRequest(page)

    open fun fetchPopularNovels(page: Int): Observable<NovelsPage> = super.fetchPopularManga(page)

    final override fun fetchPopularManga(page: Int): Observable<NovelsPage> = fetchPopularNovels(page)

    protected abstract fun searchNovelsParse(response: Response): NovelsPage

    final override fun searchMangaParse(response: Response): NovelsPage = searchNovelsParse(response)

    protected abstract fun searchNovelsRequest(
        page: Int,
        query: String,
        filters: FilterList,
    ): Request

    final override fun searchMangaRequest(
        page: Int,
        query: String,
        filters: FilterList,
    ): Request = searchNovelsRequest(page, query, filters)

    open fun fetchSearchNovels(page: Int, query: String, filters: FilterList): Observable<NovelsPage> = super.fetchSearchManga(page, query, filters)

    final override fun fetchSearchManga(page: Int, query: String, filters: FilterList): Observable<NovelsPage> = fetchSearchNovels(page, query, filters)

    @Suppress("PARAMETER_NAME_CHANGED_ON_OVERRIDE")
    override fun fetchChapterList(novel: SNovel): Observable<List<SChapter>> = super.fetchChapterList(novel)

    // fetchPageList is not invoked by host app at all
    final override fun fetchPageList(chapter: SChapter): Observable<List<Page>> = super.fetchPageList(chapter)
}
