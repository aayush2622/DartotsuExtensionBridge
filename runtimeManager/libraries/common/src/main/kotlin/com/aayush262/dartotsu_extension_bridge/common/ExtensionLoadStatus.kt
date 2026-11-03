package com.aayush262.dartotsu_extension_bridge.common

/** A backend that loads its extensions in the background reports how many are still being prepared. */
interface ExtensionLoadStatus {
    fun pendingExtensions(): Int

    /**
     * Waits up to [waitMs] for plugins to change after [since] and returns what changed as JSON:
     * `{version, entries: [{path, name, state, progress, error, sources}]}`.
     */
    suspend fun extensionChanges(since: Long, waitMs: Long): String = """{"version":0,"entries":[]}"""

    /** Looks at the extensions folder and starts preparing new or changed plugins without waiting. */
    fun scanExtensions(path: String) {}
}
