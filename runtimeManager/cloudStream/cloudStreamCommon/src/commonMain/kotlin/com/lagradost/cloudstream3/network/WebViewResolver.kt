package com.lagradost.cloudstream3.network

import com.lagradost.cloudstream3.USER_AGENT
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * Builds a [Request] for [method], attaching an empty body when [method]
 * requires one (OkHttp throws building e.g. a bodyless POST) - shared by the
 * android/desktop actuals so a plugin-supplied `method` doesn't crash either.
 */
internal fun buildWebViewRequest(
    url: String,
    method: String,
    headers: Map<String, String>,
    referer: String?,
): Request {
    val needsBody = method != "GET" && method != "HEAD"
    val builder = Request.Builder()
        .url(url)
        .method(method, if (needsBody) "".toRequestBody(null) else null)
    headers.forEach { (key, value) -> builder.header(key, value) }
    referer?.let { builder.header("referer", it) }
    return builder.build()
}

/**
 * Ported from CloudStream's `library` module (expect/actual split between
 * androidMain, which drives a real android.webkit.WebView, and desktopMain,
 * which has no WebView and degrades to a plain passthrough). Referenced by
 * plugins (e.g. AllWish.cs3) that previously failed with
 * NoClassDefFoundError because this class didn't exist here at all.
 *
 * When used as Interceptor additionalUrls cannot be returned, use WebViewResolver(...).resolveUsingWebView(...)
 * @param interceptUrl will stop the WebView when reaching this url.
 * @param additionalUrls this will make resolveUsingWebView also return all other requests matching the list of Regex.
 * @param userAgent if null then will use the default user agent
 * @param useOkhttp will try to use the okhttp client as much as possible, but this might cause some requests to fail. Disable for cloudflare.
 * @param script pass custom js to execute
 * @param scriptCallback will be called with the result from custom js
 * @param timeout close webview after timeout
 * */
expect class WebViewResolver(
    interceptUrl: Regex,
    additionalUrls: List<Regex> = emptyList(),
    userAgent: String? = USER_AGENT,
    useOkhttp: Boolean = true,
    script: String? = null,
    scriptCallback: ((String) -> Unit)? = null,
    timeout: Long = DEFAULT_TIMEOUT
) : Interceptor {
    companion object {
        val DEFAULT_TIMEOUT: Long
        var webViewUserAgent: String?
    }

    /**
     * @param requestCallBack asynchronously return matched requests by either interceptUrl or additionalUrls. If true, destroy WebView.
     * @return the final request (by interceptUrl) and all the collected urls (by additionalUrls).
     * */
    suspend fun resolveUsingWebView(
        url: String,
        referer: String? = null,
        method: String = "GET",
        requestCallBack: (Request) -> Boolean = { false },
    ): Pair<Request?, List<Request>>

    /**
     * @param requestCallBack asynchronously return matched requests by either interceptUrl or additionalUrls. If true, destroy WebView.
     * @return the final request (by interceptUrl) and all the collected urls (by additionalUrls).
     * */
    suspend fun resolveUsingWebView(
        url: String,
        referer: String? = null,
        headers: Map<String, String> = emptyMap(),
        method: String = "GET",
        requestCallBack: (Request) -> Boolean = { false },
    ): Pair<Request?, List<Request>>

    /**
     * @param requestCallBack asynchronously return matched requests by either interceptUrl or additionalUrls. If true, destroy WebView.
     * @return the final request (by interceptUrl) and all the collected urls (by additionalUrls).
     * */
    suspend fun resolveUsingWebView(
        request: Request,
        requestCallBack: (Request) -> Boolean = { false }
    ): Pair<Request?, List<Request>>
}
