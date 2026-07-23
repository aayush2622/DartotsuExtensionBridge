package eu.kanade.tachiyomi.network.interceptor

import eu.kanade.tachiyomi.network.PersistentCookieStore
import okhttp3.Interceptor

// commonMain
expect class CloudflareInterceptor(
    cookieManager: PersistentCookieStore,
    defaultUserAgentProvider: () -> String,
) : Interceptor

