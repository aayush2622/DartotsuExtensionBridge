package eu.kanade.tachiyomi.network

import com.aayush262.dartotsu_extension_bridge.customMethods
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.aayush262.dartotsu_extension_bridge.network.StoredCookieDto
import com.google.gson.Gson
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeParseException

class PersistentCookieJar(
    private val store: PersistentCookieStore,
) : CookieJar {

    override fun saveFromResponse(
        url: HttpUrl,
        cookies: List<Cookie>,
    ) {
        store.addAll(url, cookies)

        customMethods?.setCookies(
            url.toString(),
            cookies.map(::buildCookieString),
        )
    }
    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        Logger.log("Loading cookies for request: ${url.host}")
        val json = customMethods?.getCookies(url.toString())

        if (!json.isNullOrBlank()) {
            try {
                val flutterCookies = Gson().fromJson(
                    json,
                    Array<StoredCookieDto>::class.java,
                )

                val okCookies = flutterCookies.map { cookie ->
                    Cookie.Builder()
                        .name(cookie.name)
                        .value(cookie.value)
                        .apply {
                            if (cookie.hostOnly) {
                                hostOnlyDomain(cookie.domain)
                            } else {
                                domain(cookie.domain)
                            }
                        }
                        .path(cookie.path)
                        .apply {
                            if (cookie.secure) secure()
                            if (cookie.httpOnly) httpOnly()
                            cookie.expires?.let {
                                val millis = try {
                                    Instant.parse(it).toEpochMilli()
                                } catch (_: DateTimeParseException) {
                                    LocalDateTime.parse(it)
                                        .atZone(ZoneId.systemDefault())
                                        .toInstant()
                                        .toEpochMilli()
                                }

                                expiresAt(millis)
                            }
                        }
                        .build()
                }

                if (okCookies.isNotEmpty()) {
                    store.addAll(url, okCookies)
                }
            } catch (e: Exception) {
                Logger.log("Failed to parse Flutter cookies", e)
            }
        }
        val storedCookies = store.get(url)
        return storedCookies
    }
    private fun buildCookieString(cookie: Cookie): String =
        buildString {
            append("${cookie.name}=${cookie.value}")
            append("; Path=${cookie.path}")
            append("; Domain=${cookie.domain}")

            if (cookie.secure) append("; Secure")
            if (cookie.httpOnly) append("; HttpOnly")

            if (cookie.expiresAt != Long.MAX_VALUE) {
                append("; Max-Age=${(cookie.expiresAt - System.currentTimeMillis()) / 1000}")
            }
        }
}