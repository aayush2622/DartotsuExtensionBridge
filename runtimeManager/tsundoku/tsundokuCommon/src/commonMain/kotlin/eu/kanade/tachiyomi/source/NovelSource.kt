package eu.kanade.tachiyomi.source

/**
 * A marker interface for sources that provide novels.
 * Sources implementing this interface should return text content in their page lists.
 */
interface NovelSource {
    /**
     * Whether this source provides novel (text-based) content.
     * Always true for NovelSource implementations.
     * This property is used by HttpPageLoader to determine how to load pages.
     */
    val isNovelSource: Boolean
        get() = true

    /**
     * Fetches the text content for a page.
     * @param page The page to fetch text for
     * @return The text content of the page
     */
    suspend fun fetchPageText(page: eu.kanade.tachiyomi.source.model.Page): String
}
