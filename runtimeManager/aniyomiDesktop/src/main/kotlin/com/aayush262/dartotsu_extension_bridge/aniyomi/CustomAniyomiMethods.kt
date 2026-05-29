package com.aayush262.dartotsu_extension_bridge.aniyomi

import com.aayush262.dartotsu_extension_bridge.FlutterBridge


class CustomAniyomiMethods : CustomMethods {

    override fun getCookies(url: String): String? {
        return try {
            val response = FlutterBridge.call(
                "getCookies",
                mapOf("url" to url),
            )

            @Suppress("UNCHECKED_CAST")
            val cookies =
                response["result"] as? Map<String, String>
                    ?: return null

            cookies.entries.joinToString("; ") {
                "${it.key}=${it.value}"
            }
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

    override fun log(level: String, message: String) {
        FlutterBridge.call("logger", mapOf(
            "level" to level,
            "message" to "[EXT] $message"
        ))
    }
}
