package com.lagradost.cloudstream3.network

import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response

/**
 * Desktop has no WebView, so this can't actually resolve a JS challenge or
 * collect requests fired by a page - it degrades to a plain passthrough:
 * `intercept()` proceeds the original request unmodified, and
 * `resolveUsingWebView` returns the request it was given with no additional
 * URLs, rather than crashing plugins that reference this class at all
 * (previously NoClassDefFoundError, e.g. AllWish.cs3).
 * */
actual class WebViewResolver actual constructor(
    interceptUrl: Regex,
    additionalUrls: List<Regex>,
    userAgent: String?,
    useOkhttp: Boolean,
    script: String?,
    scriptCallback: ((String) -> Unit)?,
    timeout: Long
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        return chain.proceed(chain.request())
    }

    actual companion object {
        actual val DEFAULT_TIMEOUT = 60_000L
        actual var webViewUserAgent: String? = null
    }

    actual suspend fun resolveUsingWebView(
        url: String,
        referer: String?,
        method: String,
        requestCallBack: (Request) -> Boolean,
    ): Pair<Request?, List<Request>> =
        resolveUsingWebView(url, referer, emptyMap(), method, requestCallBack)

    actual suspend fun resolveUsingWebView(
        url: String,
        referer: String?,
        headers: Map<String, String>,
        method: String,
        requestCallBack: (Request) -> Boolean,
    ): Pair<Request?, List<Request>> {
        return resolveUsingWebView(buildWebViewRequest(url, method, headers, referer), requestCallBack)
    }

    actual suspend fun resolveUsingWebView(
        request: Request,
        requestCallBack: (Request) -> Boolean
    ): Pair<Request?, List<Request>> {
        requestCallBack(request)
        return request to emptyList()
    }
}
