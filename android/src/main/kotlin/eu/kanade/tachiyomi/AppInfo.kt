package eu.kanade.tachiyomi

import tachiyomi.core.util.system.ImageUtil

/**
 * Used by extensions.
 */
@Suppress("UNUSED")
object AppInfo {
    /**
     * Version code of the host application. May be useful for sharing as User-Agent information.
     * Note that this value differs between forks so logic should not rely on it.
     *
     * @since extension-lib 1.3
     */
    /**
     * Version name of the host application. May be useful for sharing as User-Agent information.
     * Note that this value differs between forks so logic should not rely on it.
     *
     * @since extension-lib 1.3
     */

    /**
     * A list of supported image MIME types by the reader.
     * e.g. ["image/jpeg", "image/png", ...]
     *
     * @since extension-lib 1.5
     */
    fun getSupportedImageMimeTypes(): List<String> = ImageUtil.ImageType.values().map { it.mime }
}
