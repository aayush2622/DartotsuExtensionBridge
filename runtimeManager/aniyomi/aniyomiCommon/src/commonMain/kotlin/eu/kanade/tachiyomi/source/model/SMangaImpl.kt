@file:Suppress("PropertyName")

package eu.kanade.tachiyomi.source.model

import kotlinx.serialization.json.JsonObject

class SMangaImpl : SManga {

    override lateinit var url: String

    override lateinit var title: String

    override var altTitles: List<String> = emptyList()

    override var thumbnail_url: String? = null

    override var banner: String? = null

    override var artist: String? = null

    override var author: String? = null

    override var status: Int = 0

    override var language: String? = null

    override var contentRating: SManga.ContentRating = SManga.ContentRating.SAFE

    override var score: Int? = null

    override var description: String? = null

    override var genres: List<String> = emptyList()

    override var readingMode: SManga.ReadingMode? = null

    override var update_strategy: UpdateStrategy = UpdateStrategy.ALWAYS_UPDATE

    override var initialized: Boolean = false

    override var memo: JsonObject = JsonObject(emptyMap())
}
