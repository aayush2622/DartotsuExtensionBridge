package com.aayush262.dartotsu_extension_bridge.common

import com.aayush262.dartotsu_extension_bridge.CommonApi

interface ExtensionBridgeApi {
    fun initialize(customMethods: BridgeCallbacks){
        CommonApi.init(customMethods)
    }
    fun initClient(data: String)
}

/**
 * Calls from a JVM backend into the Flutter app. The app owns the one cookie
 * jar, the User-Agent and the WebViews every backend shares.
 *
 * Every call blocks, so never make one from the Android main thread.
 */
interface BridgeCallbacks {
    fun getCookies(url: String): String?
    fun setCookies(url: String, cookies: List<String>)
    fun log(level: String, message: String)

    /** The app's User-Agent, the same one its WebViews send, or null if unknown. */
    fun getUserAgent(): String? = null

    /**
     * Asks the app to clear a Cloudflare challenge for [url] in a WebView.
     * Returns true once fresh clearance cookies are in the app's cookie jar.
     */
    fun solveCloudflare(url: String): Boolean = false

    /**
     * Same as above; [retried] is true when a request already went out again
     * with the app's clearance and was challenged once more, so the app knows
     * the clearance was rejected and the user has to pass it.
     */
    fun solveCloudflare(url: String, retried: Boolean): Boolean = solveCloudflare(url)

    /**
     * Runs a WebView task in the app: load a page, collect the requests it
     * makes and run a script. [request] and the result are JSON; see
     * `lib/Network/BridgeWebView.dart` for the shape. Null when unavailable.
     */
    fun webView(request: String): String? = null
}
