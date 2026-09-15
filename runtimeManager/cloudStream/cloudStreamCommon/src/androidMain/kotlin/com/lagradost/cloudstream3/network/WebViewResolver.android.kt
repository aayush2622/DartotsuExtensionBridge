package com.lagradost.cloudstream3.network

import android.annotation.SuppressLint
import android.content.Context
import android.net.http.SslError
import android.webkit.SslErrorHandler
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import com.lagradost.api.Log
import com.lagradost.api.getContext
import com.lagradost.cloudstream3.app
import com.lagradost.cloudstream3.mvvm.logError
import com.lagradost.cloudstream3.mvvm.safe
import com.lagradost.cloudstream3.utils.Coroutines.main
import com.lagradost.cloudstream3.utils.Coroutines.threadSafeListOf
import io.ktor.http.Url
import io.ktor.http.decodeURLPart
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response

/**
 * Ported from CloudStream's `library` module (android.webkit.WebView-backed
 * actual for the expect class in WebViewResolver.kt). Referenced by plugins
 * (e.g. AllWish.cs3) that previously failed with NoClassDefFoundError
 * because this class didn't exist here at all.
 * */
actual class WebViewResolver actual constructor(
    val interceptUrl: Regex,
    val additionalUrls: List<Regex>,
    val userAgent: String?,
    val useOkhttp: Boolean,
    val script: String?,
    val scriptCallback: ((String) -> Unit)?,
    val timeout: Long
) : Interceptor {

    actual companion object {
        actual var webViewUserAgent: String? = null
        actual val DEFAULT_TIMEOUT = 60_000L
        private const val TAG = "WebViewResolver"
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        return runBlocking {
            val fixedRequest = resolveUsingWebView(request).first
            chain.proceed(fixedRequest ?: request)
        }
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
        return try {
            resolveUsingWebView(buildWebViewRequest(url, method, headers, referer), requestCallBack)
        } catch (e: IllegalArgumentException) {
            logError(e)
            null to emptyList()
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    actual suspend fun resolveUsingWebView(
        request: Request,
        requestCallBack: (Request) -> Boolean
    ): Pair<Request?, List<Request>> {
        val url = request.url.toString()
        val headers = request.headers
        Log.i(TAG, "Initial web-view request: $url")
        var webView: WebView? = null
        var shouldExit = false

        fun destroyWebView() {
            main {
                webView?.stopLoading()
                webView?.destroy()
                webView = null
                shouldExit = true
                Log.i(TAG, "Destroyed webview")
            }
        }

        var fixedRequest: Request? = null
        val extraRequestList = threadSafeListOf<Request>()

        main {
            try {
                webView = WebView(
                    (getContext() as? Context)
                        ?: throw RuntimeException("No base context in WebViewResolver")
                ).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true

                    webViewUserAgent = settings.userAgentString
                    if (userAgent != null) {
                        settings.userAgentString = userAgent
                    }
                }

                webView?.webViewClient = object : WebViewClient() {
                    override fun shouldInterceptRequest(
                        view: WebView,
                        request: WebResourceRequest
                    ): WebResourceResponse? = runBlocking {
                        val webViewUrl = request.url.toString()
                        Log.i(TAG, "Loading WebView URL: $webViewUrl")

                        if (script != null) {
                            view.evaluateJavascript(script) { scriptCallback?.invoke(it) }
                        }

                        if (interceptUrl.containsMatchIn(webViewUrl)) {
                            fixedRequest = request.toRequest()?.also {
                                requestCallBack(it)
                            }
                            Log.i(TAG, "Web-view request finished: $webViewUrl")
                            destroyWebView()
                            return@runBlocking null
                        }

                        if (additionalUrls.any { it.containsMatchIn(webViewUrl) }) {
                            request.toRequest()?.also {
                                if (requestCallBack(it)) destroyWebView()
                            }?.let(extraRequestList::add)
                        }

                        val blacklistedFiles = listOf(
                            ".jpg", ".png", ".webp", ".mpg", ".mpeg", ".jpeg", ".webm",
                            ".mp4", ".mp3", ".gifv", ".flv", ".asf", ".mov", ".mng",
                            ".mkv", ".ogg", ".avi", ".wav", ".woff2", ".woff", ".ttf",
                            ".css", ".vtt", ".srt", ".ts", ".gif", "wss://"
                        )

                        return@runBlocking try {
                            when {
                                blacklistedFiles.any {
                                    Url(webViewUrl).encodedPath.decodeURLPart().contains(it)
                                } || webViewUrl.endsWith("/favicon.ico") ->
                                    WebResourceResponse("image/png", null, null)

                                webViewUrl.contains("recaptcha") || webViewUrl.contains("/cdn-cgi/") ->
                                    super.shouldInterceptRequest(view, request)

                                useOkhttp && request.method == "GET" ->
                                    app.get(webViewUrl, headers = request.requestHeaders)
                                        .okhttpResponse.toWebResourceResponse()

                                useOkhttp && request.method == "POST" ->
                                    app.post(webViewUrl, headers = request.requestHeaders)
                                        .okhttpResponse.toWebResourceResponse()

                                else -> super.shouldInterceptRequest(view, request)
                            }
                        } catch (_: Exception) {
                            null
                        }
                    }

                    @SuppressLint("WebViewClientOnReceivedSslError")
                    override fun onReceivedSslError(
                        view: WebView?,
                        handler: SslErrorHandler?,
                        error: SslError?
                    ) {
                        handler?.proceed()
                    }
                }
                webView?.loadUrl(url, headers.toMap())
            } catch (e: Exception) {
                logError(e)
            }
        }

        var loop = 0
        val totalTime = timeout
        val delayTime = 100L

        while (loop < totalTime / delayTime && !shouldExit) {
            if (fixedRequest != null) return fixedRequest to extraRequestList
            delay(delayTime)
            loop += 1
        }

        Log.i(TAG, "Web-view timeout after ${totalTime / 1000}s")
        destroyWebView()
        return fixedRequest to extraRequestList
    }
}

private fun WebResourceRequest.toRequest(): Request? {
    val webViewUrl = this.url.toString()
    return safe {
        buildWebViewRequest(webViewUrl, this.method, this.requestHeaders, referer = null)
    }
}

private fun Response.toWebResourceResponse(): WebResourceResponse {
    val contentTypeValue = this.header("Content-Type")
    val typeRegex = Regex("""(.*);(?:.*charset=(.*)(?:|;)|)""")
    return if (contentTypeValue != null) {
        val found = typeRegex.find(contentTypeValue)
        val contentType = found?.groupValues?.getOrNull(1)?.ifBlank { null } ?: contentTypeValue
        val charset = found?.groupValues?.getOrNull(2)?.ifBlank { null }
        WebResourceResponse(contentType, charset, this.body.byteStream())
    } else {
        WebResourceResponse("application/octet-stream", null, this.body.byteStream())
    }
}
