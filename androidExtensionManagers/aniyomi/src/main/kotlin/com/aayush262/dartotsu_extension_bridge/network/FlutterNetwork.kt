package com.aayush262.dartotsu_extension_bridge.network

import com.aayush262.dartotsu_extension_bridge.LogLevel
import com.aayush262.dartotsu_extension_bridge.Logger
import eu.kanade.tachiyomi.network.NetworkHelper
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.dnsoverhttps.DnsOverHttps
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import java.util.concurrent.TimeUnit

object Network {

    fun enableNetworking(data: Map<*, *>): Boolean {
        try {
           val client = Injekt.get<NetworkHelper>()
            val dns = data["dns"] as? String? ?: ""

            val dnsClient = OkHttpClient.Builder()
                .connectTimeout(5, TimeUnit.SECONDS)
                .readTimeout(5, TimeUnit.SECONDS)
                .build()
            val doh = dns.takeIf { it.isNotEmpty() }?.let {
                DnsOverHttps.Builder()
                    .client(dnsClient)
                    .url(it.toHttpUrl())
                    .build()
            }

            client.client = client.client.newBuilder()
                .dns(doh ?: client.client.dns)
                .cookieJar(WebviewCookieJar())
                .addInterceptor(CookieInterceptor())
                .addInterceptor(LogInterceptor())
                .build()

            Logger.log("Flutter networking enabled")
            return true
        } catch (e: Throwable) {
            Logger.log("Failed to enable Flutter networking: ${e.message}\n${e.stackTrace} ", LogLevel.WARNING)
            return false
        }
    }
}