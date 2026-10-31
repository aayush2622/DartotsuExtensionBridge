package com.lagradost.cloudstream3.network

import com.aayush262.dartotsu_extension_bridge.network.Cloudflare
import com.aayush262.dartotsu_extension_bridge.network.FlutterCookies
import com.aayush262.dartotsu_extension_bridge.network.Network
import okhttp3.Headers
import okhttp3.Headers.Companion.toHeaders
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response

/**
 * CloudStream's Cloudflare interceptor on the bridge's network layer: the
 * app's WebView clears the challenge and keeps the cookies in the app's
 * cookie jar, which every backend and the app's own WebView share.
 */
class CloudflareKiller : Interceptor {
    companion object {
        const val TAG = "CloudflareKiller"

        fun parseCookieMap(cookie: String): Map<String, String> =
            cookie.split(";").associate {
                val split = it.split("=", limit = 2)
                (split.getOrNull(0)?.trim() ?: "") to (split.getOrNull(1)?.trim() ?: "")
            }.filter { it.key.isNotBlank() && it.value.isNotBlank() }
    }

    /** Cookies per host as last read from the app's jar. */
    val savedCookies: MutableMap<String, Map<String, String>> = mutableMapOf()

    /**
     * Headers for requests made outside this client (a video player, for
     * example): the app's cookies for [url] and the User-Agent that goes with
     * its clearance.
     */
    fun getCookieHeaders(url: String): Headers {
        val headers = mutableMapOf("user-agent" to Network.userAgent)
        val cookies = loadCookies(url)
        if (cookies.isNotEmpty()) {
            headers["cookie"] = cookies.entries.joinToString("; ") { "${it.key}=${it.value}" }
        }
        return headers.toHeaders()
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val response = chain.proceed(request)
        if (!Cloudflare.isChallenge(response)) return response

        if (!Cloudflare.solve(request.url)) return response
        response.close()
        val retried = chain.proceed(withCookies(request))
        if (!Cloudflare.isChallenge(retried)) return retried
        if (!Cloudflare.solve(request.url, retried = true)) return retried
        retried.close()
        return chain.proceed(withCookies(request))
    }

    private fun loadCookies(url: String): Map<String, String> {
        val host = url.toHttpUrlOrNull()?.host ?: return emptyMap()
        val cookies = FlutterCookies.load(url).associate { it.name to it.value }
        if (cookies.isNotEmpty()) savedCookies[host] = cookies
        return cookies
    }

    private fun withCookies(request: Request): Request {
        val builder = request.newBuilder()
        getCookieHeaders(request.url.toString()).forEach { (name, value) -> builder.header(name, value) }
        return builder.build()
    }
}
