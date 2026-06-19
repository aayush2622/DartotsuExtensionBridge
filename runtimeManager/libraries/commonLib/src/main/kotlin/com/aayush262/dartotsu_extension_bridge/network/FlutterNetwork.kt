package com.aayush262.dartotsu_extension_bridge.network

import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.google.gson.Gson
import okhttp3.Dns
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.dnsoverhttps.DnsOverHttps
import java.net.InetAddress
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit

object Network {

    fun enableNetworking(data: String): OkHttpClient {
        try {

            val config = Gson().fromJson(
                data,
                Map::class.java
            ) as Map<*, *>


            val dns = config["dns"] as? String ?: ""
            val proxy = config["proxy"] as? String

            val dnsClient = OkHttpClient.Builder()
                .connectTimeout(5, TimeUnit.SECONDS)
                .readTimeout(5, TimeUnit.SECONDS)
                .build()
            val builder = OkHttpClient.Builder()

            if (dns.isNotBlank()) {
                try {
                    val doh = DnsOverHttps.Builder()
                        .client(dnsClient)
                        .url(dns.toHttpUrl())
                        .build()

                    builder.dns(FallbackDns(doh))

                    Logger.log("Using DoH with fallback: $dns")
                } catch (e: Exception) {
                    Logger.log(
                        "Failed to initialize DoH, using system DNS",
                        e,
                        LogLevel.WARNING
                    )
                }
            }
            Logger.log("Flutter networking enabled")
            return builder
                .cookieJar(WebviewCookieJar())
                .addInterceptor(CookieInterceptor())
                .addInterceptor(LogInterceptor())
                .build()


        } catch (e: Throwable) {
            Logger.log("Failed to enable Flutter networking: ${e.message}\n${e.stackTrace} ", LogLevel.WARNING)
            return OkHttpClient()
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

            try {
                Dns.SYSTEM.lookup(hostname)
            } catch (e2: UnknownHostException) {
                throw e2
            }
        }
    }
}