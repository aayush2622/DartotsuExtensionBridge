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
import android.webkit.CookieManager

/// [WebviewCookieJar] is technique used to sync cookies between okhttp and webview now
/// but now am too lazy to remove it
class CookieInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val url = request.url.toString()

        val cookieHeader = getCookiesBlocking(url)
        val newRequest = if (!cookieHeader.isNullOrEmpty()) {
            request.newBuilder().removeHeader("Cookie").addHeader("Cookie", cookieHeader).build()
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
    ): String? = customAniyomiMethods?.getCookies(url)


    private fun setCookies(
        url: String, cookies: List<String>
    ) = customAniyomiMethods?.setCookies(url, cookies)


}


class WebviewCookieJar : CookieJar {

    private val cookieManager = CookieManager.getInstance()

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val cookieString = cookieManager.getCookie(url.toString()) ?: return emptyList()

        return cookieString.split(";").mapNotNull { parseCookie(it.trim(), url) }.also { it ->
                if (it.isNotEmpty()) {
                    println("Loaded cookies for ${url.host}: ${it.joinToString { "${it.name}=${it.value}" }}")
                }
            }
    }

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        for (cookie in cookies) {
            val cookieString = buildCookieString(cookie)
            cookieManager.setCookie(url.toString(), cookieString)
        }

        cookieManager.flush()
    }

    private fun parseCookie(cookie: String, url: HttpUrl): Cookie? {
        val index = cookie.indexOf("=")
        if (index <= 0) return null

        val name = cookie.substring(0, index).trim()
        val value = cookie.substring(index + 1).trim()

        return Cookie.Builder().name(name).value(value).domain(url.host).path("/").build()
    }

    private fun buildCookieString(cookie: Cookie): String {
        return buildString {
            append("${cookie.name}=${cookie.value}; Path=${cookie.path};")

            if (cookie.secure) append(" Secure;")
            if (cookie.httpOnly) append(" HttpOnly;")

            append(" Domain=${cookie.domain};")
        }
    }
}