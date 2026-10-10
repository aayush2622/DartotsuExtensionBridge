package eu.kanade.tachiyomi.network.interceptor

import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.network.POST
import eu.kanade.tachiyomi.network.PersistentCookieStore
import eu.kanade.tachiyomi.network.awaitSuccess
import eu.kanade.tachiyomi.network.parseAs
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.Cookie
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import uy.kohesive.injekt.injectLazy
import java.io.IOException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeoutException
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.toJavaDuration

actual class CloudflareInterceptor actual constructor(
    cookieManager: PersistentCookieStore,
    defaultUserAgentProvider: () -> String,
) : Interceptor {
    private val network: NetworkHelper by injectLazy()

    private val setUserAgent: (String) -> Unit = { network.setUserAgent(it) }

    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()
        val originalResponse = chain.proceed(originalRequest)

        if (!(originalResponse.code in ERROR_CODES && originalResponse.header("Server") in SERVER_CHECK)) {
            return originalResponse
        }

        Logger.log("Cloudflare anti-bot is on, CloudflareInterceptor is kicking in...", LogLevel.DEBUG)

        return try {
            originalResponse.close()
            resolveCloudflare(chain, originalRequest, originalResponse)
        } catch (e: Exception) {
            // OkHttp's enqueue only handles IOExceptions
            throw IOException(e)
        }
    }

    private fun resolveCloudflare(
        chain: Interceptor.Chain,
        originalRequest: Request,
        originalResponse: Response,
    ): Response {
        val host = originalRequest.url.host

        while (true) {
            val bypassRequest = CompletableFuture<CFClearance.Result>()
            val inflightRequest = CFClearance.inflightCalls.putIfAbsent(host, bypassRequest)

            if (inflightRequest != null) {
                Logger.log("Waiting for inflight call for host $host", LogLevel.DEBUG)

                when (val result = awaitInflightResult(inflightRequest)) {
                    is CFClearance.Result.CloudflareBypassed -> {
                        val request = CFClearance.buildRequestWithStoredCookies(originalRequest, result.userAgent)
                        return chain.proceed(request)
                    }

                    is CFClearance.Result.CloudflareNotDetected -> {
                        Logger.log("Inflight call did not detect Cloudflare for $host, retrying", LogLevel.DEBUG)
                        continue
                    }
                }
            }

            Logger.log("Calling FlareSolverr for host $host", LogLevel.DEBUG)
            try {
                val flareResponse = runBlocking {
                    CFClearance.resolveWithFlareSolver(originalRequest, !FLARE_RESPONSE_FALLBACK)
                }

                val cloudflareDetected = !flareResponse.message.contains("not detected", ignoreCase = true)
                return if (cloudflareDetected) {
                    val request = CFClearance.requestWithFlareSolverr(flareResponse, setUserAgent, originalRequest)
                    bypassRequest.complete(CFClearance.Result.CloudflareBypassed(flareResponse.solution.userAgent))

                    chain.proceed(request)
                } else {
                    CFClearance.inflightCalls.remove(host, bypassRequest)
                    bypassRequest.complete(CFClearance.Result.CloudflareNotDetected)

                    maybeFallbackToFlareSolverResponse(flareResponse, chain, originalRequest, originalResponse)
                }
            } catch (e: Exception) {
                val failure = if (e is java.net.ConnectException || e.cause is java.net.ConnectException) {
                    IOException(
                        "$host is behind Cloudflare and FlareSolverr is not reachable at " +
                            "${CFClearance.FLARESOLVERR_URL}. Start FlareSolverr to use this source.",
                        e,
                    )
                } else {
                    e
                }
                bypassRequest.completeExceptionally(failure)
                throw failure
            } finally {
                CFClearance.inflightCalls.remove(host, bypassRequest)
            }
        }
    }

    private fun maybeFallbackToFlareSolverResponse(
        flareResponse: CFClearance.FlareSolverResponse,
        chain: Interceptor.Chain,
        originalRequest: Request,
        originalResponse: Response,
    ): Response {
        Logger.log("FlareSolverr failed to detect Cloudflare challenge", LogLevel.DEBUG)

        if (FLARE_RESPONSE_FALLBACK &&
            flareResponse.solution.status in 200..299 &&
            flareResponse.solution.response != null
        ) {
            val isImage = flareResponse.solution.response.contains(CHROME_IMAGE_TEMPLATE_REGEX)
            if (!isImage) {
                setUserAgent(flareResponse.solution.userAgent)

                return originalResponse
                    .newBuilder()
                    .code(flareResponse.solution.status)
                    .body(flareResponse.solution.response.toResponseBody())
                    .build()
            }
        }

        val request = CFClearance.requestWithFlareSolverr(flareResponse, setUserAgent, originalRequest)
        return chain.proceed(request)
    }

    private fun awaitInflightResult(future: CompletableFuture<CFClearance.Result>): CFClearance.Result {
        while (true) {
            try {
                return future.get()
            } catch (_: TimeoutException) {
                continue
            } catch (e: ExecutionException) {
                throw e.cause ?: e
            }
        }
    }

    companion object {
        private val ERROR_CODES = listOf(403, 503)
        private val SERVER_CHECK = arrayOf("cloudflare-nginx", "cloudflare")
        val COOKIE_NAMES = listOf("cf_clearance")
        private val CHROME_IMAGE_TEMPLATE_REGEX = Regex("""<title>(.*?) \(\d+×\d+\)</title>""")
        private const val FLARE_RESPONSE_FALLBACK = false
    }
}

/*
 * This class is ported from https://github.com/vvanglro/cf-clearance
 * The original code is licensed under Apache 2.0
*/
object CFClearance {
    const val FLARESOLVERR_URL = "http://localhost:8191"
    private const val SESSION_NAME = "dartotsu"
    private val SESSION_TTL_MINUTES = 15.minutes.inWholeMinutes.toInt()
    private val TIMEOUT = 60.seconds

    private val network: NetworkHelper by injectLazy()
    private val client by lazy {
        network.client
            .newBuilder()
            .callTimeout(TIMEOUT.plus(10.seconds).toJavaDuration())
            .readTimeout(TIMEOUT.plus(5.seconds).toJavaDuration())
            .build()
    }
    private val json: Json by injectLazy()
    private val jsonMediaType = "application/json".toMediaType()
    private val mutex = Mutex()

    sealed class Result {
        data class CloudflareBypassed(val userAgent: String) : Result()

        data object CloudflareNotDetected : Result()
    }

    val inflightCalls = ConcurrentHashMap<String, CompletableFuture<Result>>()

    fun buildRequestWithStoredCookies(request: Request, userAgent: String): Request {
        val cookies = network.cookieStore.get(request.url).joinToString("; ", postfix = "; ") {
            "${it.name}=${it.value}"
        }

        return request
            .newBuilder()
            .header("Cookie", cookies)
            .header("User-Agent", userAgent)
            .build()
    }

    @Serializable
    data class FlareSolverCookie(
        val name: String,
        val value: String,
    )

    @Serializable
    data class FlareSolverRequest(
        val cmd: String,
        val url: String,
        val maxTimeout: Int? = null,
        val session: String? = null,
        @SerialName("session_ttl_minutes") val sessionTtlMinutes: Int? = null,
        val cookies: List<FlareSolverCookie>? = null,
        val returnOnlyCookies: Boolean? = null,
        val postData: String? = null, // only used with cmd 'request.post'
    )

    @Serializable
    data class FlareSolverSolutionCookie(
        val name: String,
        val value: String,
        val domain: String,
        val path: String? = null,
        val expires: Double? = null,
        val size: Int? = null,
        val httpOnly: Boolean? = null,
        val secure: Boolean? = null,
        val session: Boolean? = null,
        val sameSite: String? = null,
    )

    @Serializable
    data class FlareSolverSolution(
        val url: String,
        val status: Int,
        val headers: Map<String, String>? = null,
        val response: String? = null,
        val cookies: List<FlareSolverSolutionCookie>,
        val userAgent: String,
    )

    @Serializable
    data class FlareSolverResponse(
        val solution: FlareSolverSolution,
        val status: String,
        val message: String,
        val startTimestamp: Long,
        val endTimestamp: Long,
        val version: String,
    )

    suspend fun resolveWithFlareSolver(
        originalRequest: Request,
        onlyCookies: Boolean,
    ): FlareSolverResponse {
        return with(json) {
            mutex.withLock {
                client.newCall(
                    POST(
                        url = FLARESOLVERR_URL.removeSuffix("/") + "/v1",
                        body = Json.encodeToString(
                            FlareSolverRequest(
                                "request.${originalRequest.method.lowercase()}",
                                originalRequest.url.toString(),
                                session = SESSION_NAME,
                                sessionTtlMinutes = SESSION_TTL_MINUTES,
                                cookies = network.cookieStore
                                    .get(originalRequest.url)
                                    .filter { it.name !in CloudflareInterceptor.COOKIE_NAMES }
                                    .map { FlareSolverCookie(it.name, it.value) },
                                returnOnlyCookies = onlyCookies,
                                maxTimeout = TIMEOUT.inWholeMilliseconds.toInt(),
                                postData = if (originalRequest.method == "POST") {
                                    originalRequest.body
                                        ?.let { body -> Buffer().also { body.writeTo(it) }.readUtf8() }
                                        .orEmpty()
                                } else {
                                    null
                                },
                            ),
                        ).toRequestBody(jsonMediaType),
                    ),
                ).awaitSuccess().parseAs<FlareSolverResponse>()
            }
        }
    }

    fun requestWithFlareSolverr(
        flareSolverResponse: FlareSolverResponse,
        setUserAgent: (String) -> Unit,
        originalRequest: Request,
    ): Request {
        if (flareSolverResponse.solution.cookies.none { it.name in CloudflareInterceptor.COOKIE_NAMES }) {
            Logger.log("Cloudflare challenge failed to resolve", LogLevel.DEBUG)
            throw CloudflareBypassException()
        }

        setUserAgent(flareSolverResponse.solution.userAgent)
        flareSolverResponse.solution.cookies
            .map { cookie ->
                Cookie.Builder()
                    .name(cookie.name)
                    .value(cookie.value)
                    .domain(cookie.domain.removePrefix("."))
                    .also {
                        if (cookie.httpOnly != null && cookie.httpOnly) it.httpOnly()
                        if (cookie.secure != null && cookie.secure) it.secure()
                        if (!cookie.path.isNullOrEmpty()) it.path(cookie.path)
                        // expires is seconds; the persistent cookie store wants milliseconds
                        if (cookie.expires != null && cookie.expires > 0) it.expiresAt((cookie.expires * 1000).toLong())
                        if (!cookie.domain.startsWith('.')) {
                            it.hostOnlyDomain(cookie.domain.removePrefix("."))
                        }
                    }.build()
            }.groupBy { it.domain }
            .forEach { (domain, cookies) ->
                network.cookieStore.addAll(
                    HttpUrl.Builder().scheme("http").host(domain.removePrefix(".")).build(),
                    cookies,
                )
            }

        return buildRequestWithStoredCookies(originalRequest, flareSolverResponse.solution.userAgent)
    }

    private class CloudflareBypassException : Exception()
}
