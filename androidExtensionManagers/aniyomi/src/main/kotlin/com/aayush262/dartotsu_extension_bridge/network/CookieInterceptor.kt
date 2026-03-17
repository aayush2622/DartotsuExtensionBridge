package com.aayush262.dartotsu_extension_bridge.network

import com.aayush262.dartotsu_extension_bridge.customAniyomiMethods
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
