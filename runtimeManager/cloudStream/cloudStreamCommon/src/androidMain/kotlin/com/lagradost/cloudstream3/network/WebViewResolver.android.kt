package com.lagradost.cloudstream3.network

import com.aayush262.dartotsu_extension_bridge.network.BridgeWebView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response

/**
 * Runs the page in the Flutter app's background WebView
 * (`lib/Network/BridgeWebView.dart`), with the app's cookies, and collects
 * the requests it makes that match [interceptUrl] and [additionalUrls].
 *
 * The page's own User-Agent is the app's, so [userAgent] is not applied. A
 * request matched in the WebView is rebuilt with that User-Agent and the
 * page as its referer; the WebView's other request headers aren't visible.
 */
actual class WebViewResolver actual constructor(
    val interceptUrl: Regex,
    val additionalUrls: List<Regex>,
    val userAgent: String?,
    val useOkhttp: Boolean,
    val script: String?,
    val scriptCallback: ((String) -> Unit)?,
    val timeout: Long
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val resolved = runBlocking { resolveUsingWebView(request) { false }.first }
        return chain.proceed(resolved ?: request)
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
    ): Pair<Request?, List<Request>> = withContext(Dispatchers.IO) {
        val pageUrl = request.url.toString()
        val headers = request.headers.toMap().filterKeys { !it.equals("user-agent", ignoreCase = true) }

        val result = BridgeWebView.resolve(
            url = pageUrl,
            headers = headers,
            interceptUrl = interceptUrl,
            additionalUrls = additionalUrls,
            script = script,
            timeoutMs = timeout,
        ) ?: return@withContext null to emptyList()

        result.userAgent?.let { webViewUserAgent = it }
        result.scriptResult?.let { scriptCallback?.invoke(it) }

        fun toRequest(url: String) = Request.Builder()
            .url(url)
            .apply {
                result.userAgent?.let { header("User-Agent", it) }
                header("Referer", pageUrl)
            }
            .build()

        val main = result.url?.let(::toRequest)
        val extra = result.additional.map(::toRequest)
        for (matched in listOfNotNull(main) + extra) {
            if (requestCallBack(matched)) break
        }
        main to extra
    }
}
