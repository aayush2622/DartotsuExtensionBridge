@file:Suppress("PropertyName")

package eu.kanade.tachiyomi.source.model

import kotlinx.serialization.json.JsonObject
import java.io.Serializable

interface SChapter : Serializable {

    var url: String

    var name: String

    /**
     * Volume number in string format, validated against
     * `^(?:-?\d+(?:\.\d+)?[a-z]?|nan)$` — e.g. `"1"`, `"1.5"`, `"1a"`, `"-1"`, `"nan"`, or `null`
     * for unnumbered volumes.
     *
     * @since tachiyomix 1.7
     */
    var volume: String?

    /**
     * Chapter number in string format, same grammar as [volume].
     *
     * Replaces the `Float` [chapter_number] from tachiyomix 1.6 and earlier, which is kept as a
     * bridge over this property.
     *
     * @since tachiyomix 1.7
     */
    var number: String?

    /**
     * Scanlation groups credited for this chapter.
     *
     * Replaces the single [scanlator] string from tachiyomix 1.6 and earlier.
     *
     * @since tachiyomix 1.7
     */
    var scanlators: List<String>

    var date_upload: Long

    /**
     * Language of the chapter content as an IETF BCP 47 tag. A `null` value should be treated as
     * [SManga.language].
     *
     * @since tachiyomix 1.7
     */
    var language: String?

    /**
     * Whether the chapter is currently locked — payment, waiting, or authentication required.
     *
     * @since tachiyomix 1.7
     */
    var locked: Boolean

    /**
     * Free-form, source-defined note shown alongside the chapter.
     *
     * @since tachiyomix 1.7
     */
    var note: String?

    /**
     * Extra metadata associated with the chapter.
     *
     * The JSON object is not visible to users and intended for internal or source-specific
     * purposes. Apps may define their own namespaced keys (e.g., `"mihon.*"`) for sources to populate.
     *
     * This allows apps to attach and ask for custom information without affecting the visible
     * chapter data.
     *
     * @since tachiyomix 1.6
     */
    var memo: JsonObject

    /**
     * Numeric view over [number], `-1f` when there is no parseable number.
     *
     * Retained for extensions built against tachiyomix 1.6 and earlier.
     */
    @Deprecated("Use number", ReplaceWith("number"))
    var chapter_number: Float
        get() = number?.toFloatOrNull() ?: -1f
        set(value) {
            number = when {
                value < 0f -> null
                value == value.toLong().toFloat() -> value.toLong().toString()
                else -> value.toString()
            }
        }

    /**
     * Single-string view over [scanlators].
     *
     * Retained for extensions built against tachiyomix 1.6 and earlier.
     */
    @Deprecated("Use scanlators", ReplaceWith("scanlators"))
    var scanlator: String?
        get() = scanlators.takeIf { it.isNotEmpty() }?.joinToString(", ")
        set(value) {
            scanlators = value
                ?.split(",")
                ?.map { it.trim() }
                ?.filterNot { it.isBlank() }
                ?: emptyList()
        }

    fun copyFrom(other: SChapter) {
        name = other.name
        url = other.url
        volume = other.volume
        number = other.number
        scanlators = other.scanlators
        date_upload = other.date_upload
        language = other.language
        locked = other.locked
        note = other.note
        memo = other.memo
    }

    companion object {
        fun create(): SChapter {
            return SChapterImpl()
        }
    }
}
