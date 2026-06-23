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

class CookieInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val url = request.url.toString()

        val cookieHeader = getCookiesBlocking(url)

        val newRequest = if (!cookieHeader.isNullOrEmpty()) {
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

    private fun getCookiesBlocking(
        url: String
    ): String? = customMethods?.getCookies(url)


    private fun setCookies(
        url: String, cookies: List<String>
    ) = customMethods?.setCookies(url, cookies)


}


class WebviewCookieJar : CookieJar {

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val cookieHeader = getCookiesBlocking(url.toString())
            ?: return emptyList()

        return cookieHeader
            .split(";")
            .mapNotNull { parseCookie(it.trim(), url) }
    }

    override fun saveFromResponse(
        url: HttpUrl,
        cookies: List<Cookie>
    ) {
        val setCookies = cookies.map { buildCookieString(it) }

        if (setCookies.isNotEmpty()) {
            setCookies(
                url.toString(),
                setCookies,
            )
        }
    }

    private fun parseCookie(
        cookie: String,
        url: HttpUrl,
    ): Cookie? {
        val index = cookie.indexOf('=')

        if (index <= 0) {
            return null
        }

        val name = cookie.substring(0, index).trim()
        val value = cookie.substring(index + 1).trim()

        return Cookie.Builder()
            .name(name)
            .value(value)
            .domain(url.host)
            .path("/")
            .build()
    }

    private fun buildCookieString(
        cookie: Cookie,
    ): String {
        return buildString {
            append("${cookie.name}=${cookie.value}")

            append("; Path=${cookie.path}")

            append("; Domain=${cookie.domain}")

            if (cookie.secure) {
                append("; Secure")
            }

            if (cookie.httpOnly) {
                append("; HttpOnly")
            }

            cookie.expiresAt.takeIf {
                it != Long.MAX_VALUE
            }?.let {
                append("; Max-Age=${(it - System.currentTimeMillis()) / 1000}")
            }
        }
    }

    private fun getCookiesBlocking(
        url: String,
    ): String? = customMethods?.getCookies(url)

    private fun setCookies(
        url: String,
        cookies: List<String>,
    ) = customMethods?.setCookies(url, cookies)
}