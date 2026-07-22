package eu.kanade.tachiyomi.network

import android.content.Context
import eu.kanade.tachiyomi.network.interceptor.CloudflareInterceptor
import eu.kanade.tachiyomi.network.interceptor.UncaughtExceptionInterceptor
import eu.kanade.tachiyomi.network.interceptor.UserAgentInterceptor
import kotlinx.coroutines.flow.MutableStateFlow
import okhttp3.Cache
import okhttp3.OkHttpClient
import okhttp3.brotli.BrotliInterceptor
import java.io.File
import java.net.CookieHandler
import java.net.CookieManager
import java.net.CookiePolicy
import java.util.concurrent.TimeUnit

class NetworkHelper(
    context: Context
) {
    val cookieStore = PersistentCookieStore(context)

    init {
        CookieHandler.setDefault(
            CookieManager(cookieStore, CookiePolicy.ACCEPT_ALL),
        )
    }

    var client: OkHttpClient = run {
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
            .addInterceptor(UserAgentInterceptor(::defaultUserAgentProvider))
            .addInterceptor(
                CloudflareInterceptor(setUserAgent = { userAgent.value = it }),
            )
        builder.build()
    }


    /**
     * @deprecated Since extension-lib 1.5
     */
    @Deprecated("The regular client handles Cloudflare by default")
    @Suppress("UNUSED")
    val cloudflareClient: OkHttpClient = client
    private val userAgent =
        MutableStateFlow(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        )

    fun defaultUserAgentProvider(): String = userAgent.value

}