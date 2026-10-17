package com.aayush262.dartotsu_extension_bridge.ireader

import com.aayush262.dartotsu_extension_bridge.network.Network
import com.aayush262.dartotsu_extension_bridge.network.NetworkBound
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import ireader.core.http.HttpClientsInterface
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/**
 * iReader's HTTP clients on the bridge's shared network layer (the app's
 * DNS, proxy, User-Agent and cookie jar, and Cloudflare challenges cleared by
 * the app's WebView). Everything else comes from [delegate].
 */
class BridgeHttpClients(
    private val delegate: HttpClientsInterface,
) : HttpClientsInterface by delegate {

    private val client = NetworkBound {
        HttpClient(OkHttp) {
            engine {
                preconfigured = Network.applyTo(
                    OkHttpClient.Builder()
                        .connectTimeout(30, TimeUnit.SECONDS)
                        .readTimeout(30, TimeUnit.SECONDS)
                ).build()
            }
            install(ContentNegotiation) {
                json(Json {
                    ignoreUnknownKeys = true
                    isLenient = true
                    explicitNulls = false
                })
            }
        }
    }

    override val default: HttpClient
        get() = client.get()

    override val cloudflareClient: HttpClient
        get() = default
}
