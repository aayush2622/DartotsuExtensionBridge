@file:Suppress("PropertyName")

package eu.kanade.tachiyomi.source.model

import kotlinx.serialization.json.JsonObject
import java.io.Serializable

interface SManga : Serializable {

    var url: String

    var title: String

    /**
     * Alternative titles for the manga: official translations, romanizations, or other titles the
     * series is known by in different regions or languages.
     *
     * @since tachiyomix 1.7
     */
    var altTitles: List<String>

    var thumbnail_url: String?

    /**
     * URL of the manga's banner image — typically a wide image shown in headers or detail views.
     *
     * @since tachiyomix 1.7
     */
    var banner: String?

    var artist: String?

    var author: String?

    var status: Int

    /**
     * Primary language of the manga as an IETF BCP 47 tag (`"en"`, `"zh-Hant"`, `"mul"`, `"und"`).
     * A `null` value should be treated as the source's own language.
     *
     * @since tachiyomix 1.7
     */
    var language: String?

    /**
     * Age or content rating for the manga. Defaults to [ContentRating.SAFE].
     *
     * @since tachiyomix 1.7
     */
    var contentRating: ContentRating

    /**
     * Source-provided rating as a percentile (0..100), or `null` when unavailable.
     *
     * @since tachiyomix 1.7
     */
    var score: Int?

    var description: String?

    /**
     * Genres of the manga.
     *
     * Replaces the comma-joined [genre] string from tachiyomix 1.6 and earlier; [genre] is kept as
     * a bridge over this list so already-published extensions keep working.
     *
     * @since tachiyomix 1.7
     */
    var genres: List<String>

    /**
     * Comma-joined view over [genres].
     *
     * Retained for extensions built against tachiyomix 1.6 and earlier, which read and write a
     * single `", "`-separated string.
     */
    @Deprecated("Use genres", ReplaceWith("genres"))
    var genre: String?
        get() = genres.takeIf { it.isNotEmpty() }?.joinToString(", ")
        set(value) {
            genres = value
                ?.split(",")
                ?.map { it.trim() }
                ?.filterNot { it.isBlank() }
                ?.distinct()
                ?: emptyList()
        }

    /**
     * Preferred reading mode provided by the source, or `null` when the source mixes modes and
     * gives no explicit signal.
     *
     * @since tachiyomix 1.7
     */
    var readingMode: ReadingMode?

    var update_strategy: UpdateStrategy

    var initialized: Boolean

    /**
     * Extra metadata associated with the manga.
     *
     * The JSON object is not visible to users and intended for internal or source-specific
     * purposes. Apps may define their own namespaced keys (e.g., `"mihon.*"`) for sources to populate.
     *
     * This allows apps to attach and ask for custom information without affecting the visible
     * manga data.
     *
     * @since tachiyomix 1.6
     */
    var memo: JsonObject

    @Suppress("DEPRECATION")
    fun copy() = create().also {
        it.url = url
        it.title = title
        it.altTitles = altTitles
        it.artist = artist
        it.author = author
        it.description = description
        it.genres = genres
        it.status = status
        it.thumbnail_url = thumbnail_url
        it.banner = banner
        it.language = language
        it.contentRating = contentRating
        it.score = score
        it.readingMode = readingMode
        it.update_strategy = update_strategy
        it.initialized = initialized
        it.memo = memo
    }

    /**
     * @since tachiyomix 1.7
     */
    enum class ContentRating {
        SAFE,
        SUGGESTIVE,
        ADULT,
    }

    /**
     * @since tachiyomix 1.7
     */
    enum class ReadingMode {
        RIGHT_TO_LEFT,
        LEFT_TO_RIGHT,
        LONG_STRIP,
    }

    companion object {
        const val UNKNOWN = 0
        const val ONGOING = 1
        const val COMPLETED = 2
        const val LICENSED = 3
        const val PUBLISHING_FINISHED = 4
        const val CANCELLED = 5
        const val ON_HIATUS = 6

        fun create(): SManga {
            return SMangaImpl()
        }
    }
}
