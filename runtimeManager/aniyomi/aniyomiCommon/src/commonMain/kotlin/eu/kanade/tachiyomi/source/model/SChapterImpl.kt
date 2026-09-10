@file:Suppress("PropertyName")

package eu.kanade.tachiyomi.source.model

import kotlinx.serialization.json.JsonObject

class SChapterImpl : SChapter {

    override lateinit var url: String

    override lateinit var name: String

    override var volume: String? = null

    override var number: String? = null

    override var scanlators: List<String> = emptyList()

    override var date_upload: Long = 0

    override var language: String? = null

    override var locked: Boolean = false

    override var note: String? = null

    override var memo: JsonObject = JsonObject(emptyMap())
}
