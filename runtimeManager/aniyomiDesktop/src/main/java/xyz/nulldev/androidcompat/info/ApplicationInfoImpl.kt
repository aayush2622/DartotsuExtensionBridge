package xyz.nulldev.androidcompat.info

import android.content.pm.ApplicationInfo

/**
 * Dartotsu version - no config dependency
 */
class ApplicationInfoImpl(
    packageName: String = "dartotsu.app",
    debug: Boolean = false,
) : ApplicationInfo() {

    val debugMode: Boolean = debug

    init {
        this.packageName = packageName

        // Optional flags (some extensions may check this)
        this.flags = if (debug) {
            FLAG_DEBUGGABLE
        } else {
            0
        }
    }
}