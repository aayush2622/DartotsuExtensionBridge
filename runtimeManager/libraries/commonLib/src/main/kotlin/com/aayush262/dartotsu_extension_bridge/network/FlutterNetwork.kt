package com.aayush262.dartotsu_extension_bridge.network

import com.aayush262.dartotsu_extension_bridge.customMethods
import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.google.gson.Gson
import okhttp3.Dns
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.dnsoverhttps.DnsOverHttps
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.util.concurrent.TimeUnit

const val DEFAULT_USER_AGENT =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

/**
 * The network layer every JVM backend shares, so they all behave like the
 * Flutter app: same DNS-over-HTTPS resolver and proxy, the app's live
 * User-Agent, the app's cookie jar, and Cloudflare challenges cleared by the
 * app's WebView ([CloudflareInterceptor]).
 *
 * Backends either take [newClient] as is, or [applyTo] their own builder when
 * they need their own cookie jar or cache.
 */
object Network {

    private data class Config(
        val dns: String = "",
        val proxy: String? = null,
        val userAgent: String? = null,
    )

    @Volatile
    private var config = Config()

    /** Bumped by every [configure], so clients built earlier can be rebuilt ([NetworkBound]). */
    @Volatile
    var version = 0
        private set

    @Volatile
    private var appUserAgent: String? = null

    @Volatile
    private var appUserAgentAt = 0L

    private const val USER_AGENT_TTL_MS = 30_000L

    /**
     * The app's User-Agent. It changes when the user edits it or a WebView
     * reports the real one, so it is re-read from the app every 30 seconds.
     * Cloudflare ties its clearance cookie to the User-Agent that solved the
     * challenge, which is the app's.
     */
    val userAgent: String
        get() {
            val now = System.currentTimeMillis()
            if (now - appUserAgentAt > USER_AGENT_TTL_MS) {
                appUserAgentAt = now
                runCatching { customMethods?.getUserAgent() }.getOrNull()
                    ?.takeIf { it.isNotBlank() }
                    ?.let { appUserAgent = it }
            }
            return appUserAgent ?: config.userAgent?.ifBlank { null } ?: DEFAULT_USER_AGENT
        }

    /** Forgets the cached User-Agent so the next request asks the app again. */
    fun refreshUserAgent() {
        appUserAgentAt = 0L
    }

    /** Reads `{dns, proxy, userAgent}` sent by the Flutter side's `initClient`. */
    fun configure(data: String) {
        config = try {
            val map = Gson().fromJson(data, Map::class.java) as Map<*, *>
            Config(
                dns = (map["dns"] as? String)?.trim().orEmpty(),
                proxy = (map["proxy"] as? String)?.trim()?.ifBlank { null },
                userAgent = (map["userAgent"] as? String)?.trim()?.ifBlank { null },
            )
        } catch (e: Exception) {
            Logger.log("Could not read the network settings, using defaults", e, LogLevel.WARNING)
            Config()
        }
        config.userAgent?.let { appUserAgent = it }
        appUserAgentAt = System.currentTimeMillis()
        version++
    }

    /**
     * Adds the shared DNS, proxy and interceptors to [builder].
     *
     * With [mergeCookies] the app's cookies are merged into every request and
     * `Set-Cookie` responses are saved back to the app. Pass false when the
     * builder already has a cookie jar backed by the app (such as
     * [FlutterCookieJar]), so cookies aren't fetched twice.
     */
    fun applyTo(builder: OkHttpClient.Builder, mergeCookies: Boolean = true): OkHttpClient.Builder {
        val current = config
        var resolver: Dns? = null

        if (current.dns.isNotBlank()) {
            try {
                val dnsClient = OkHttpClient.Builder()
                    .connectTimeout(5, TimeUnit.SECONDS)
                    .readTimeout(5, TimeUnit.SECONDS)
                    .build()
                val doh = DnsOverHttps.Builder()
                    .client(dnsClient)
                    .url(current.dns.toHttpUrl())
                    .build()
                resolver = FallbackDns(doh)
            } catch (e: Exception) {
                Logger.log("Failed to initialize DoH, using system DNS", e, LogLevel.WARNING)
            }
        }
        if (IPv4OnlyDns.required) {
            resolver = IPv4OnlyDns(resolver ?: Dns.SYSTEM)
        }
        resolver?.let { builder.dns(it) }

        current.proxy?.let { proxy ->
            try {
                val (host, port) = proxy.substringAfter("://").split(":", limit = 2)
                val type = if (proxy.startsWith("socks", ignoreCase = true)) Proxy.Type.SOCKS else Proxy.Type.HTTP
                builder.proxy(Proxy(type, InetSocketAddress(host, port.trimEnd('/').toInt())))
            } catch (e: Exception) {
                Logger.log("Failed to parse proxy \"$proxy\" (expected host:port), ignoring", e, LogLevel.WARNING)
            }
        }

        // Earlier application interceptors run first, so the User-Agent is set
        // before a challenge is detected and retried.
        builder.interceptors().removeAll { it is UserAgentInterceptor || it is CloudflareInterceptor }
        builder.interceptors().add(0, UserAgentInterceptor())
        builder.interceptors().add(1, CloudflareInterceptor())

        // Network interceptors see every redirect hop and the final Cookie
        // header, including what a cookie jar added.
        builder.networkInterceptors().removeAll { it is CookieInterceptor || it is LogInterceptor }
        builder.addNetworkInterceptor(CookieInterceptor(mergeCookies))
        builder.addNetworkInterceptor(LogInterceptor())
        return builder
    }

    /** A client with the shared layer and the app's cookies. */
    fun newClient(): OkHttpClient = applyTo(OkHttpClient.Builder()).build()

    /** Kept for callers of the old API: configures and returns [newClient]. */
    fun enableNetworking(data: String): OkHttpClient {
        configure(data)
        Logger.log("Flutter networking enabled")
        return newClient()
    }
}

/**
 * A value built from the current network settings (usually a client) that
 * is rebuilt on first use after the app sends new ones.
 */
class NetworkBound<T : Any>(private val build: () -> T) {
    @Volatile
    private var value: T? = null

    @Volatile
    private var builtFor = -1

    fun get(): T {
        value?.takeIf { builtFor == Network.version }?.let { return it }
        synchronized(this) {
            val current = value
            if (current != null && builtFor == Network.version) return current
            val version = Network.version
            return build().also {
                value = it
                builtFor = version
            }
        }
    }
}

class FallbackDns(
    private val doh: DnsOverHttps,
) : Dns {

    override fun lookup(hostname: String): List<InetAddress> {
        return try {
            doh.lookup(hostname)
        } catch (e: Exception) {
            Logger.log(
                "DoH failed for $hostname → fallback: ${e.javaClass.simpleName}: ${e.message}",
                LogLevel.WARNING
            )
            Dns.SYSTEM.lookup(hostname)
        }
    }
}

class IPv4OnlyDns(
    private val delegate: Dns,
) : Dns {

    override fun lookup(hostname: String): List<InetAddress> {
        val all = delegate.lookup(hostname)
        val v4 = all.filter { it is java.net.Inet4Address }
        return v4.ifEmpty { all }
    }

    companion object {
        val required: Boolean by lazy {
            System.getProperty("java.net.preferIPv4Stack").toBoolean() ||
                System.getProperty("dartotsu.runtime") == "ios"
        }
    }
}
