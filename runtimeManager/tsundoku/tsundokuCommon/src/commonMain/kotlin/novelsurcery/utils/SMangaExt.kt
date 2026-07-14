package novelsurcery.utils

import eu.kanade.tachiyomi.source.model.SManga

/**
 * Safely set alternative titles on an SManga instance.
 * Uses reflection to remain compatible with any version of extensions-lib.
 * On Tsundoku (which adds altTitles to SManga), this sets the property directly.
 * On other apps without the property, this silently does nothing.
 */
@Suppress("UNCHECKED_CAST")
fun SManga.setAltTitles(titles: List<String>) {
    try {
        this::class.java.getMethod("setAltTitles", List::class.java)
            .invoke(this, titles)
    } catch (_: Exception) {
        // altTitles property not available on this version of extensions-lib
    }
}
