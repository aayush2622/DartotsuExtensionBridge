package com.aayush262.dartotsu_extension_bridge.cloudStream

import com.lagradost.cloudstream3.MainAPI

/** Android extensions show their own settings screens. */
actual object SourcePreferences {
    actual fun get(provider: MainAPI): String = "[]"
    actual fun save(provider: MainAPI, key: String, value: String?): Boolean = false
}
