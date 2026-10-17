package com.aayush262.dartotsu_extension_bridge

import com.google.gson.Gson
import com.google.gson.JsonObject
import okhttp3.Dispatcher
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

object FlutterBridge {

    private val client = OkHttpClient.Builder()
        .dispatcher(
            Dispatcher().apply {
                maxRequests = 10000
                maxRequestsPerHost = 10000
            }
        )
        .build()
    private val gson = Gson()

    // WebView tasks wait on page loads and, for a challenge the background
    // WebView can't clear, on the user.
    private val slowClient by lazy {
        client.newBuilder()
            .readTimeout(6, TimeUnit.MINUTES)
            .callTimeout(6, TimeUnit.MINUTES)
            .build()
    }

    fun call(
        method: String,
        args: Map<String, Any?> = emptyMap(),
        slow: Boolean = false,
    ): JsonObject {

        return runCatching {

            val requestBody =
                gson.toJson(
                    mapOf(
                        "method" to method,
                        "args" to args,
                    ),
                )

            val request =
                Request.Builder()
                    .url("http://127.0.0.1:4567")
                    .post(
                        requestBody.toRequestBody(
                            "application/json".toMediaType(),
                        ),
                    )
                    .build()

            (if (slow) slowClient else client).newCall(request)
                .execute()
                .use { response ->

                    gson.fromJson(
                        response.body.charStream(),
                        JsonObject::class.java,
                    )
                }

        }.getOrElse { error ->
            JsonObject().apply {
                addProperty(
                    "success",
                    false,
                )

                addProperty(
                    "error",
                    error.message
                        ?: error::class.java.simpleName,
                )
            }
        }
    }
}