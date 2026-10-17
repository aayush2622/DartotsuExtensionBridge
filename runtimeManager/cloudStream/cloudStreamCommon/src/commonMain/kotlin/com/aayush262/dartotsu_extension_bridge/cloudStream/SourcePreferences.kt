package com.aayush262.dartotsu_extension_bridge.cloudStream

import com.lagradost.cloudstream3.MainAPI

/**
 * A CloudStream extension's settings as the bridge's preference JSON
 * (`[{key, type, title, summary, value}]`, see `mapToSourcePreference` on the
 * Dart side), and writing one back.
 */
expect object SourcePreferences {
    fun get(provider: MainAPI): String
    fun save(provider: MainAPI, key: String, value: String?): Boolean
}
