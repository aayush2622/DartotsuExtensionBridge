package com.aayush262.dartotsu_extension_bridge.ireader.prefs

import ireader.core.prefs.PreferenceStore

expect class PreferenceStoreFactory {
    fun create(vararg names: String, rootPath: String): PreferenceStore
}