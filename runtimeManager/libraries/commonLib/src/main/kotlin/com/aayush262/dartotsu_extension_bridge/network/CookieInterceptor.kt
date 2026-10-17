package com.aayush262.dartotsu_extension_bridge.network

import okhttp3.Interceptor
import okhttp3.Response
import java.io.IOException

/**
 * Network interceptor that keeps every request on the app's cookie jar.
 *
 * With [merge], the app's cookies for the URL are added to the request
 * (cookies the request already carries win), and `Set-Cookie` responses are
 * saved back to the app. Without it the client's own cookie jar does that.
 *
 * Either way, a request carrying `cf_clearance` is sent with the app's
 * User-Agent: Cloudflare rejects a clearance cookie sent with any other.
 */
class CookieInterceptor(private val merge: Boolean = true) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val url = request.url.toString()

        var cookieHeader = request.header("Cookie").orEmpty()
        if (merge) {
            val present = cookieHeader.split(';').map { it.substringBefore('=').trim() }.toSet()
            val extra = FlutterCookies.load(url)
                .filter { it.name !in present }
                .joinToString("; ") { "${it.name}=${it.value}" }
            if (extra.isNotEmpty()) {
                cookieHeader = if (cookieHeader.isBlank()) extra else "$cookieHeader; $extra"
            }
        }

        val builder = request.newBuilder()
        if (cookieHeader.isNotBlank()) builder.header("Cookie", cookieHeader)
        if (hasClearance(cookieHeader)) builder.header("User-Agent", Network.userAgent)

        val response = try {
            chain.proceed(builder.build())
        } catch (e: IOException) {
            throw e
        } catch (e: Throwable) {
            throw IOException(e.message, e)
        }

        if (merge) {
            val setCookies = response.headers("Set-Cookie")
            if (setCookies.isNotEmpty()) FlutterCookies.save(url, setCookies)
        }
        return response
    }

    private fun hasClearance(header: String) =
        header.split(';').any { it.trim().startsWith("cf_clearance=") }
}
