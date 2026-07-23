package eu.kanade.tachiyomi.network.interceptor

import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.network.POST
import eu.kanade.tachiyomi.network.PersistentCookieStore
import eu.kanade.tachiyomi.network.awaitSuccess
import eu.kanade.tachiyomi.network.parseAs
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.Cookie
import okhttp3.FormBody
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
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.toJavaDuration

actual class CloudflareInterceptor actual constructor(
    cookieManager: PersistentCookieStore, defaultUserAgentProvider: () -> String
) : Interceptor {
    private var currentUserAgent = defaultUserAgentProvider()

    private val setUserAgent: (String) -> Unit = {
        currentUserAgent = it
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()
        val originalResponse = chain.proceed(originalRequest)

        // Check if Cloudflare anti-bot is on
        if (!(originalResponse.code in ERROR_CODES && originalResponse.header("Server") in SERVER_CHECK)) {
            return originalResponse
        }

        return try {
            originalResponse.close()
            // network.cookieStore.remove(originalRequest.url.toUri())

            val flareResponse = runBlocking {
                CFClearance.resolveWithFlareSolver(originalRequest, true)
            }

            if (flareResponse.message.contains("not detected", ignoreCase = true)) {

                if (flareResponse.solution.status in 200..299 && flareResponse.solution.response != null) {
                    val isImage = flareResponse.solution.response.contains(CHROME_IMAGE_TEMPLATE_REGEX)
                    if (!isImage) {


                        setUserAgent(flareResponse.solution.userAgent)

                        return originalResponse.newBuilder().code(flareResponse.solution.status).body(flareResponse.solution.response.toResponseBody()).build()
                    }
                }
            }

            val request = CFClearance.requestWithFlareSolverr(flareResponse, setUserAgent, originalRequest)

            chain.proceed(request)
        } catch (e: Exception) {
            // Because OkHttp's enqueue only h logger.debug { "FlareSolverr response is an image html template, not falling back" }
            //                    }andles IOExceptions, wrap the exception so that
            // we don't crash the entire app
            throw IOException(e)
        }
    }


}

private val ERROR_CODES = listOf(403, 503)
private val SERVER_CHECK = arrayOf("cloudflare-nginx", "cloudflare")
val COOKIE_NAMES = listOf("cf_clearance")
private val CHROME_IMAGE_TEMPLATE_REGEX = Regex("""<title>(.*?) \(\d+×\d+\)</title>""")

/*
 * This class is ported from https://github.com/vvanglro/cf-clearance
 * The original code is licensed under Apache 2.0
*/
object CFClearance {

    private val network: NetworkHelper by injectLazy()
    val client by lazy {
        @Suppress("OPT_IN_USAGE")

        val timeout = 60.seconds.inWholeSeconds.toInt().seconds
        network.client.newBuilder().callTimeout(timeout.plus(10.seconds).toJavaDuration()).readTimeout(timeout.plus(5.seconds).toJavaDuration()).build()

    }
    private val json: Json by injectLazy()
    private val jsonMediaType = "application/json".toMediaType()
    private val mutex = Mutex()

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
        val proxy: String? = null,
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
        val timeout = 60.seconds.inWholeSeconds.toInt().seconds
        return with(json) {
            mutex.withLock {
                client.newCall(
                    POST(
                        url = "http://localhost:8191".removeSuffix("/") + "/v1",
                        body = Json.encodeToString(
                            FlareSolverRequest(
                                "request.${originalRequest.method.lowercase()}",
                                originalRequest.url.toString(),
                                session = "dartotsu",
                                sessionTtlMinutes = 15.minutes.inWholeMinutes.toInt(),
                                cookies = network.cookieStore.get(originalRequest.url).filter { it.name !in COOKIE_NAMES }.map { cookie ->
                                    FlareSolverCookie(cookie.name, cookie.value)
                                },
                                returnOnlyCookies = onlyCookies,
                                maxTimeout = timeout.inWholeMilliseconds.toInt(),
                                postData = if (originalRequest.method == "POST") {
                                    when (val body = originalRequest.body) {
                                        is FormBody -> {
                                            Buffer().also { body.writeTo(it) }.readUtf8()
                                        }

                                        else -> {
                                            ""
                                        }
                                    }
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
        if (flareSolverResponse.solution.status in 200..299) {
            setUserAgent(flareSolverResponse.solution.userAgent)
            val cookies = flareSolverResponse.solution.cookies.map { cookie ->
                Cookie.Builder().name(cookie.name).value(cookie.value).domain(cookie.domain.removePrefix(".")).also {
                    if (cookie.httpOnly != null && cookie.httpOnly) it.httpOnly()
                    if (cookie.secure != null && cookie.secure) it.secure()
                    if (!cookie.path.isNullOrEmpty()) it.path(cookie.path)
                    // We need to convert the expires time to milliseconds for the persistent cookie store
                    if (cookie.expires != null && cookie.expires > 0) it.expiresAt((cookie.expires * 1000).toLong())
                    if (!cookie.domain.startsWith('.')) {
                        it.hostOnlyDomain(cookie.domain.removePrefix("."))
                    }
                }.build()
            }.groupBy { it.domain }.flatMap { (domain, cookies) ->
                network.cookieStore.addAll(
                    HttpUrl.Builder().scheme("http").host(domain.removePrefix(".")).build(),
                    cookies,
                )

                cookies
            }

            val finalCookies = network.cookieStore.get(originalRequest.url).joinToString("; ", postfix = "; ") {
                "${it.name}=${it.value}"
            }

            return originalRequest.newBuilder().header("Cookie", finalCookies).header("User-Agent", flareSolverResponse.solution.userAgent).build()
        } else {
            throw CloudflareBypassException()
        }
    }

    private class CloudflareBypassException : Exception()
}
