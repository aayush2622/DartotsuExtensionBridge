package org.koitharu.kotatsu.parsers

import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Response
import org.koitharu.kotatsu.parsers.bitmap.Bitmap
import org.koitharu.kotatsu.parsers.config.MangaSourceConfig
import org.koitharu.kotatsu.parsers.model.MangaSource
import org.koitharu.kotatsu.parsers.webview.InterceptedRequest
import org.koitharu.kotatsu.parsers.webview.InterceptionConfig
import org.koitharu.kotatsu.parsers.util.LinkResolver
import java.util.*

abstract class MangaLoaderContext {

	abstract val httpClient: OkHttpClient

	abstract val cookieJar: CookieJar

	abstract fun newParserInstance(source: MangaSource): MangaParser

	abstract fun getParserSources(): List<MangaSource>

	fun newLinkResolver(link: HttpUrl): LinkResolver = LinkResolver(link, context = this)

	fun newLinkResolver(link: String): LinkResolver = newLinkResolver(link.toHttpUrl())

	open fun encodeBase64(data: ByteArray): String = Base64.getEncoder().encodeToString(data)

	open fun decodeBase64(data: String): ByteArray = Base64.getDecoder().decode(data)

	open fun getPreferredLocales(): List<Locale> = listOf(Locale.getDefault())

	/**
	 * Execute JavaScript code and return result
	 * @param script JavaScript source code
	 * @return execution result as string, may be null
	 */
	@Deprecated("Provide a base url")
	abstract suspend fun evaluateJs(script: String): String?

	/**
	 * Execute JavaScript code and return result
	 * @param script JavaScript source code
	 * @param baseUrl url of page script will be executed in context of
	 * @return execution result as string, may be null
	 */
	abstract suspend fun evaluateJs(baseUrl: String, script: String): String?

	/**
	 * Same as [evaluateJs] with a [timeout] (ms); newer parsers call this form.
	 */
	open suspend fun evaluateJs(baseUrl: String, script: String, timeout: Long): String? =
		evaluateJs(baseUrl, script)

	open fun requestCloudflareVerification(parser: MangaParser, url: String): Nothing {
		requestBrowserAction(parser, url)
	}

	open suspend fun interceptWebViewRequests(
		url: String,
		interceptorScript: String,
		timeout: Long = 30000L,
	): List<InterceptedRequest> {
		throw UnsupportedOperationException("WebView request interception is not available")
	}

	open suspend fun interceptWebViewRequests(
		url: String,
		config: InterceptionConfig,
	): List<InterceptedRequest> =
		interceptWebViewRequests(url, config.filterScript ?: "return true;", config.timeoutMs)

	open suspend fun captureWebViewUrls(
		pageUrl: String,
		urlPattern: Regex,
		timeout: Long = 30000L,
	): List<String> {
		throw UnsupportedOperationException("WebView URL capture is not available")
	}

	/**
	 * Open [url] in browser for some external action (e.g. captcha solving or non cookie-based authorization)
	 */
	open fun requestBrowserAction(parser: MangaParser, url: String): Nothing {
		throw UnsupportedOperationException("Browser is not available")
	}

	abstract fun getConfig(source: MangaSource): MangaSourceConfig

	abstract fun getDefaultUserAgent(): String

	/**
	 * Helper function to be used in an interceptor
	 * to descramble images
	 * @param response Image response
	 * @param redraw lambda function to implement descrambling logic
	 */
	abstract fun redrawImageResponse(
		response: Response,
		redraw: (image: Bitmap) -> Bitmap,
	): Response

	/**
	 * create a new empty Bitmap with given dimensions
	 */
	abstract fun createBitmap(
		width: Int,
		height: Int,
	): Bitmap
}
