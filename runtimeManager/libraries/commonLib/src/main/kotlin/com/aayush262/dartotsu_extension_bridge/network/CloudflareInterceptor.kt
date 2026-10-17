package com.aayush262.dartotsu_extension_bridge.network

import com.aayush262.dartotsu_extension_bridge.customMethods
import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.Response
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/**
 * Clears Cloudflare challenges with the app's WebView, then retries.
 *
 * The app solves the challenge in a background WebView (and asks the user
 * only when that fails), stores the clearance cookies in its cookie jar and
 * reports back. The retry goes through [CookieInterceptor] again, which picks
 * up the new cookies and the matching User-Agent. A challenge the app could
 * not clear returns the original response.
 */
class CloudflareInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val response = chain.proceed(request)
        if (!Cloudflare.isChallenge(response)) return response

        Logger.log("Cloudflare challenge on ${request.url.host}, asking the app to clear it", LogLevel.DEBUG)
        if (!Cloudflare.solve(request.url)) return response

        response.close()
        val retried = chain.proceed(request.newBuilder().header("User-Agent", Network.userAgent).build())
        if (!Cloudflare.isChallenge(retried)) return retried

        // The clearance the app reported did not pass; the app asks the user this time.
        Logger.log("Cloudflare still blocks ${request.url.host} after clearing, asking again", LogLevel.DEBUG)
        if (!Cloudflare.solve(request.url)) return retried
        retried.close()
        return chain.proceed(request.newBuilder().header("User-Agent", Network.userAgent).build())
    }
}

object Cloudflare {
    private val inflight = ConcurrentHashMap<String, CompletableFuture<Boolean>>()
    private val challengeStatus = setOf(403, 429, 503)
    private val markers = listOf(
        "cf-chl", "challenge-platform", "cf_chl_opt", "<title>just a moment",
        "cf-turnstile", "checking your browser", "enable javascript and cookies to continue",
    )

    /** Whether [response] is a Cloudflare challenge page (not a plain block). */
    fun isChallenge(response: Response): Boolean {
        if (response.code !in challengeStatus) return false
        if (response.header("cf-mitigated").equals("challenge", ignoreCase = true)) return true
        val server = response.header("Server")?.lowercase() ?: return false
        if (!server.startsWith("cloudflare")) return false
        val body = runCatching { response.peekBody(64 * 1024).string().lowercase() }.getOrDefault("")
        return markers.any { it in body }
    }

    /**
     * Asks the app to clear the challenge for [url]. Concurrent requests to
     * the same host share one attempt. Returns true once the app has fresh
     * clearance cookies.
     */
    fun solve(url: HttpUrl): Boolean {
        val callbacks = customMethods ?: return false
        val mine = CompletableFuture<Boolean>()
        val running = inflight.putIfAbsent(url.host, mine)
        if (running != null) {
            return runCatching { running.get(6, TimeUnit.MINUTES) }.getOrDefault(false)
        }
        return try {
            val solved = runCatching { callbacks.solveCloudflare(url.toString()) }.getOrDefault(false)
            if (solved) Network.refreshUserAgent()
            Logger.log(
                if (solved) "Cloudflare cleared for ${url.host}" else "Cloudflare not cleared for ${url.host}",
                LogLevel.DEBUG,
            )
            mine.complete(solved)
            solved
        } catch (e: Throwable) {
            mine.complete(false)
            false
        } finally {
            inflight.remove(url.host, mine)
        }
    }
}
