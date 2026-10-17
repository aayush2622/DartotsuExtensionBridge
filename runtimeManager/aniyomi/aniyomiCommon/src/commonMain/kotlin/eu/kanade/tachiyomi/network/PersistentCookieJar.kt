package eu.kanade.tachiyomi.network

import com.aayush262.dartotsu_extension_bridge.customMethods
import com.aayush262.dartotsu_extension_bridge.network.FlutterCookieJar
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl

/**
 * The app's cookie jar, mirrored into [store] for code that reads the
 * `java.net` cookie store. Without the app (a bare sidecar), [store] alone.
 */
class PersistentCookieJar(
    private val store: PersistentCookieStore,
) : CookieJar {

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        store.addAll(url, cookies)
        FlutterCookieJar.saveFromResponse(url, cookies)
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        if (customMethods == null) return store.get(url)
        val cookies = FlutterCookieJar.loadForRequest(url)
        if (cookies.isNotEmpty()) store.addAll(url, cookies)
        return cookies
    }
}
