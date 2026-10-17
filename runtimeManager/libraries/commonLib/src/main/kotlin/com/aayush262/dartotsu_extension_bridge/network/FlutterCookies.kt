package com.aayush262.dartotsu_extension_bridge.network

import com.aayush262.dartotsu_extension_bridge.customMethods
import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.google.gson.Gson
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

/** Cookie as the app's jar stores it (`BridgeNetwork.getCookies`). */
data class StoredCookieDto(
    val name: String,
    val value: String,
    val domain: String,
    val hostOnly: Boolean,
    val path: String,
    val expires: String?,
    val secure: Boolean,
    val httpOnly: Boolean,
)

/** Reads and writes the Flutter app's cookie jar. */
object FlutterCookies {
    private val gson = Gson()

    fun load(url: String): List<StoredCookieDto> {
        val json = runCatching { customMethods?.getCookies(url) }.getOrNull()
        if (json.isNullOrBlank()) return emptyList()
        return try {
            gson.fromJson(json, Array<StoredCookieDto>::class.java).toList()
        } catch (e: Exception) {
            Logger.log("Could not read the app's cookies for $url", e, LogLevel.WARNING)
            emptyList()
        }
    }

    fun save(url: String, setCookieHeaders: List<String>) {
        if (setCookieHeaders.isEmpty()) return
        runCatching { customMethods?.setCookies(url, setCookieHeaders) }
    }

    fun toOkHttp(cookie: StoredCookieDto): Cookie? = runCatching {
        Cookie.Builder()
            .name(cookie.name)
            .value(cookie.value)
            .apply { if (cookie.hostOnly) hostOnlyDomain(cookie.domain) else domain(cookie.domain) }
            .path(cookie.path.ifBlank { "/" })
            .apply {
                if (cookie.secure) secure()
                if (cookie.httpOnly) httpOnly()
                cookie.expires?.let { expiresAt(parseExpiry(it)) }
            }
            .build()
    }.getOrNull()

    /** Formats [cookie] as a `Set-Cookie` header value for the app's jar. */
    fun toSetCookie(cookie: Cookie): String = buildString {
        append("${cookie.name}=${cookie.value}")
        append("; Path=${cookie.path}")
        if (!cookie.hostOnly) append("; Domain=${cookie.domain}")
        if (cookie.secure) append("; Secure")
        if (cookie.httpOnly) append("; HttpOnly")
        if (cookie.persistent) {
            append("; Max-Age=${((cookie.expiresAt - System.currentTimeMillis()) / 1000).coerceAtLeast(0)}")
        }
    }

    private fun parseExpiry(value: String): Long = try {
        Instant.parse(value).toEpochMilli()
    } catch (_: Exception) {
        LocalDateTime.parse(value).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
    }
}

/**
 * An OkHttp [CookieJar] that is the app's cookie jar, for backends whose
 * sources read or write cookies through the client's jar. Use it with
 * `Network.applyTo(builder, mergeCookies = false)`.
 */
object FlutterCookieJar : CookieJar {
    override fun loadForRequest(url: HttpUrl): List<Cookie> =
        FlutterCookies.load(url.toString()).mapNotNull(FlutterCookies::toOkHttp)

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        FlutterCookies.save(url.toString(), cookies.map(FlutterCookies::toSetCookie))
    }
}
