package eu.kanade.tachiyomi.network.interceptor

import eu.kanade.tachiyomi.network.PersistentCookieStore
import okhttp3.Interceptor
import okhttp3.Response
import com.aayush262.dartotsu_extension_bridge.network.CloudflareInterceptor as BridgeCloudflareInterceptor

/**
 * Tachiyomi's Cloudflare interceptor, kept for sources that add it
 * themselves. The bridge's client already clears challenges with the app's
 * WebView; this does the same.
 */
@Suppress("UNUSED_PARAMETER")
class CloudflareInterceptor(
    cookieManager: PersistentCookieStore,
    defaultUserAgentProvider: () -> String,
) : Interceptor {
    private val delegate = BridgeCloudflareInterceptor()

    override fun intercept(chain: Interceptor.Chain): Response = delegate.intercept(chain)

    companion object {
        val COOKIE_NAMES = listOf("cf_clearance")
    }
}
