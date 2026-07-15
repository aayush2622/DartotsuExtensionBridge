package com.aayush262.dartotsu_extension_bridge.network

import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.Response
import kotlin.collections.List
import kotlin.collections.isNotEmpty
import kotlin.text.isNullOrEmpty
import com.aayush262.dartotsu_extension_bridge.customMethods
import com.google.gson.Gson

class CookieInterceptor : Interceptor {

    private val gson = Gson()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val url = request.url.toString()

        val json = getCookiesBlocking(url)

        val newRequest = if (!json.isNullOrBlank()) {
            val cookies = gson.fromJson(
                json,
                Array<StoredCookieDto>::class.java,
            )

            val cookieHeader = cookies.joinToString("; ") {
                "${it.name}=${it.value}"
            }

            val existing = request.header("Cookie")

            val merged = buildString {
                if (!existing.isNullOrBlank()) {
                    append(existing)
                }

                if (cookieHeader.isNotBlank()) {
                    if (isNotEmpty()) append("; ")
                    append(cookieHeader)
                }
            }

            request.newBuilder()
                .header("Cookie", merged)
                .build()
        } else {
            request
        }

        val response = chain.proceed(newRequest)

        val setCookies = response.headers("Set-Cookie")
        if (setCookies.isNotEmpty()) {
            setCookies(url, setCookies)
        }

        return response
    }

    private fun getCookiesBlocking(url: String): String? =
        customMethods?.getCookies(url)

    private fun setCookies(
        url: String,
        cookies: List<String>,
    ) {
        customMethods?.setCookies(url, cookies)
    }
}
data class StoredCookieDto(
    val name: String,
    val value: String,
    val domain: String,
    val hostOnly: Boolean,
    val path: String,
    val expires: String?,
    val secure: Boolean,
    val httpOnly: Boolean,
)