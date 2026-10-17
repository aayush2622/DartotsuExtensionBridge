package eu.kanade.tachiyomi.source

import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga

interface SourceTracker {
    val supportsChapterTracking: Boolean

    val supportsFavoritesTracking: Boolean

    suspend fun onChaptersRead(
        manga: SManga,
        readChapters: List<SChapter>,
        unreadChapters: List<SChapter>,
        allChapters: List<SChapter>,
    )

    suspend fun onFavorited(manga: SManga, chapters: List<SChapter>)

    suspend fun onUnfavorited(manga: SManga, chapters: List<SChapter>)
}
