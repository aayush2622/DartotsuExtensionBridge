package eu.kanade.tachiyomi.animesource.model

import fi.iki.elonen.NanoHTTPD

/**
 * @since extensions-lib 17
 */
open class HttpServer : NanoHTTPD(0) {
    val url: String
        get() = "http://localhost:$listeningPort"

    fun isRunning(): Boolean {
        return isRunning
    }

    @Volatile
    private var isRunning = false

    override fun start() {
        try {
            super.start()
            isRunning = true
        } catch (e: Exception) {
            // Match upstream's fire-and-forget behavior: the app-side caller
            // treats a still-not-running server as the failure signal.
        }
    }

    override fun stop() {
        super.stop()
        isRunning = false
    }

    companion object {
        const val PLACEHOLDER_URL = "http://localhost:1"
    }
}
