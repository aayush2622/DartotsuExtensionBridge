package eu.kanade.tachiyomi.network

import android.content.Context
import com.aayush262.dartotsu_extension_bridge.network.Network
import eu.kanade.tachiyomi.network.interceptor.UncaughtExceptionInterceptor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.Cache
import okhttp3.OkHttpClient
import java.io.File
import java.net.CookieHandler
import java.net.CookieManager
import java.net.CookiePolicy
import java.util.concurrent.TimeUnit

/**
 * Tachiyomi's network entry point, on the bridge's shared network layer: the
 * app's DNS, proxy, User-Agent and cookie jar, and Cloudflare challenges
 * cleared by the app's WebView.
 */
class NetworkHelper(
    private val context: Context
) {
    val cookieStore = PersistentCookieStore(context)

    init {
        CookieHandler.setDefault(
            CookieManager(cookieStore, CookiePolicy.ACCEPT_ALL),
        )
    }

    private val userAgent = MutableStateFlow(Network.userAgent)
    val userAgentFlow = userAgent.asStateFlow()

    /** The app owns the User-Agent; this only updates what the flow reports. */
    fun setUserAgent(value: String) {
        userAgent.value = value
    }

    /** The app's User-Agent. Sources build their default headers from it. */
    fun defaultUserAgentProvider(): String = Network.userAgent.also { userAgent.value = it }

    var client: OkHttpClient = buildClient()

    /** Rebuilds [client] after the app sends new network settings. */
    fun rebuildClient() {
        client = buildClient()
    }

    private fun buildClient(): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .cookieJar(PersistentCookieJar(cookieStore))
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .callTimeout(2, TimeUnit.MINUTES)
            .cache(
                Cache(
                    directory = File(context.externalCacheDir ?: context.cacheDir, "network_cache"),
                    maxSize = 5L * 1024 * 1024, // 5 MiB
                ),
            )
            .addInterceptor(UncaughtExceptionInterceptor())
        return Network.applyTo(builder, mergeCookies = false).build()
    }

    /**
     * @deprecated Since extension-lib 1.5
     */
    @Deprecated("The regular client handles Cloudflare by default")
    @Suppress("UNUSED")
    val cloudflareClient: OkHttpClient
        get() = client
}
