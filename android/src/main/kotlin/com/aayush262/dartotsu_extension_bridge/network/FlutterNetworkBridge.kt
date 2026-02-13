package com.aayush262.dartotsu_extension_bridge.network

import LogInterceptor
import android.util.Log
import eu.kanade.tachiyomi.network.NetworkHelper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.dnsoverhttps.DnsOverHttps
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object FlutterNetworkBridge {

    @Volatile
    var channel: MethodChannel? = null

    fun init(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "network_bridge")
        if (channel == null) {
            Log.e("DartotsuExtensionBridge", "Failed to initialize MethodChannel")
            return
        }
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initClient" -> {
                    val args = call.arguments as? Map<*, *> ?: return@setMethodCallHandler result.error("INVALID_ARGUMENTS", "Expected a map of arguments", null)
                    enableFlutterNetworking(args);
                    var client = Injekt.get<NetworkHelper>()
                    Log.d( "DartotsuExtensionBridge", "Flutter networking enabled");
                    result.success(null)
                }
                "testRequest" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val client = Injekt.get<NetworkHelper>()
                            val response = client.client.newCall(
                                Request.Builder()
                                    .url(call.arguments as String)
                                    .build()
                            ).execute()

                            withContext(Dispatchers.Main) {
                                result.success(response.code)
                            }
                        } catch (t: Throwable) {
                            withContext(Dispatchers.Main) {
                                result.error("REQUEST_FAILED", t.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun enableFlutterNetworking(data: Map<*, *>) {
        try {
            var client = Injekt.get<NetworkHelper>()
            var dns = data["dns"] as? String? ?: ""

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
                .addInterceptor(LogInterceptor())
                .addInterceptor(CookieInterceptor(channel))
                .build()
        } catch (t: Throwable) {
            // log, but never crash
        }

    }
    fun detach() {
        channel = null
    }
}