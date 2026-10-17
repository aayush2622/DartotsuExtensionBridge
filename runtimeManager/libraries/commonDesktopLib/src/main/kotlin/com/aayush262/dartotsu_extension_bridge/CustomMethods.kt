package com.aayush262.dartotsu_extension_bridge

import com.aayush262.dartotsu_extension_bridge.common.BridgeCallbacks


class CustomMethods : BridgeCallbacks {

    override fun getCookies(url: String): String? {
        return try {
            val response = FlutterBridge.call(
                "getCookies",
                mapOf("url" to url),
            )
            response["result"]?.takeUnless { it.isJsonNull }?.asString
        } catch (_: Exception) {
            null
        }
    }

    override fun setCookies(
        url: String,
        cookies: List<String>,
    ) {
        FlutterBridge.call(
            "setCookies",
            mapOf(
                "url" to url,
                "cookies" to cookies,
            ),
        )
    }

    override fun getUserAgent(): String? = try {
        FlutterBridge.call("getUserAgent")["result"]?.takeUnless { it.isJsonNull }?.asString
    } catch (_: Exception) {
        null
    }

    override fun solveCloudflare(url: String): Boolean = try {
        FlutterBridge.call("solveCloudflare", mapOf("url" to url), slow = true)["result"]
            ?.takeUnless { it.isJsonNull }?.asBoolean == true
    } catch (_: Exception) {
        false
    }

    override fun webView(request: String): String? = try {
        FlutterBridge.call("webView", mapOf("request" to request), slow = true)["result"]
            ?.takeUnless { it.isJsonNull }?.asString
    } catch (_: Exception) {
        null
    }

    override fun log(level: String, message: String) {
        val response = FlutterBridge.call("logger", mapOf(
            "level" to level,
            "message" to "[EXT] $message"
        ))
        // The host captures stdout, so a log the loopback server refused is not lost.
        if (response["success"]?.asBoolean != true) {
            println("[$level] $message")
        }
    }
}
