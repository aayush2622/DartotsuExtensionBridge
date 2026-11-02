package com.lagradost.cloudstream3

import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.aayush262.dartotsu_extension_bridge.network.Network
import com.lagradost.cloudstream3.utils.Event
import com.lagradost.nicehttp.Requests
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/**
 * Compatibility file for CloudStream plugins.
 * Some plugins depend on package-level properties in MainActivityKt (generated from MainActivity.kt).
 */

/** A client on the bridge's shared network layer (app DNS, proxy, User-Agent, cookies, Cloudflare). */
fun bridgeClient(): OkHttpClient = Network.applyTo(
    OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
).build()

val api: Requests get() = app

// Upstream is an object; plugins read CommonActivity.INSTANCE.
object CommonActivity {
    var activity: android.app.Activity? = null
    var isPipDesired: Boolean = false
    var isInPIPMode: Boolean = false

    fun setActivityInstance(newActivity: android.app.Activity?) {
        activity = newActivity
    }

    fun showToast(message: String?, duration: Int? = null) {
        if (!message.isNullOrBlank()) Logger.log("[Toast] $message")
    }

    fun showToast(message: Int, duration: Int? = null) {}

    fun showToast(act: android.app.Activity?, message: String?, duration: Int? = null) = showToast(message, duration)

    fun showToast(act: android.app.Activity?, message: Int, duration: Int? = null) {}
}

class MainActivity : android.app.Activity() {
    companion object {
        var context: android.content.Context? = null
        var activity: android.app.Activity? = null
        var lastError: String? = null
        val afterPluginsLoadedEvent = Event<Boolean>()
        val mainPluginsLoadedEvent = Event<Boolean>()
        val reloadHomeEvent = Event<Boolean>()
        val reloadLibraryEvent = Event<Boolean>()
        val reloadAccountEvent = Event<Boolean>()
        val bookmarksUpdatedEvent = Event<Boolean>()
    }
}
