package com.aayush262.dartotsu_extension_bridge.network

import com.aayush262.dartotsu_extension_bridge.customAniyomiMethods
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.Response
import kotlin.collections.List
import kotlin.collections.isNotEmpty
import kotlin.text.isNullOrEmpty

class CookieInterceptor : Interceptor {


    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val url = request.url.toString()

        val cookieHeader = getCookiesBlocking(url)
        val newRequest = if (!cookieHeader.isNullOrEmpty()) {
            request.newBuilder()
                .removeHeader("Cookie")
                .addHeader("Cookie", cookieHeader)
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
    ): String? {
        return customAniyomiMethods?.getCookies(url)

    }

    private fun setCookies(
        url: String,
        cookies: List<String>
    ) {
        customAniyomiMethods?.setCookies(url, cookies)
    }

}

class FlutterCookieJar : CookieJar {

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val cookieHeader = customAniyomiMethods?.getCookies(url.toString())
            ?: return emptyList()

        println("🍪 Raw cookie header: $cookieHeader")

        return cookieHeader.split(";")
            .mapNotNull { parseCookie(it.trim(), url) }
    }

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        val cookieStrings = cookies.map { "${it.name}=${it.value}" }
        customAniyomiMethods?.setCookies(url.toString(), cookieStrings)
    }

    private fun parseCookie(cookie: String, url: HttpUrl): Cookie? {
        val index = cookie.indexOf("=")
        if (index <= 0) return null

        val name = cookie.substring(0, index).trim()
        val value = cookie.substring(index + 1).trim()

        return Cookie.Builder()
            .name(name)
            .value(value)
            .domain(getValidDomain(url.host))
            .path("/")
            .build()
    }

    private fun getValidDomain(host: String): String {
        return when {
            host.endsWith("google.com") -> ".google.com"
            else -> host
        }
    }
}