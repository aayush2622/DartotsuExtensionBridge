package com.aayush262.dartotsu_extension_bridge.network

import com.aayush262.dartotsu_extension_bridge.customMethods
import com.google.gson.Gson
import com.google.gson.JsonObject

/**
 * WebView tasks run by the Flutter app (`lib/Network/BridgeWebView.dart`),
 * for backends whose sources need a real browser: requests a page makes,
 * script results, or both.
 */
object BridgeWebView {
    private val gson = Gson()

    data class Result(
        /** First request URL that matched `interceptUrl`, or null. */
        val url: String?,
        /** Every request URL that matched one of `additionalUrls`. */
        val additional: List<String>,
        /** What `script` returned, as a string, or null. */
        val scriptResult: String?,
        /** User-Agent the page was loaded with. */
        val userAgent: String?,
    )

    /**
     * Loads [url] in a background WebView with the app's User-Agent and
     * cookies, and collects request URLs matching [interceptUrl] (stopping
     * at the first) and [additionalUrls]. When [script] is set it runs after
     * the page loads, and the task waits for its result.
     */
    fun resolve(
        url: String,
        headers: Map<String, String> = emptyMap(),
        interceptUrl: Regex? = null,
        additionalUrls: List<Regex> = emptyList(),
        script: String? = null,
        timeoutMs: Long = 60_000L,
    ): Result? {
        val request = mapOf(
            "url" to url,
            "headers" to headers,
            "interceptUrl" to interceptUrl?.pattern,
            "additionalUrls" to additionalUrls.map { it.pattern },
            "script" to script,
            "timeoutMs" to timeoutMs,
        )
        val raw = runCatching { customMethods?.webView(gson.toJson(request)) }.getOrNull() ?: return null
        return runCatching {
            val json = gson.fromJson(raw, JsonObject::class.java)
            Result(
                url = json.get("url")?.takeUnless { it.isJsonNull }?.asString,
                additional = json.getAsJsonArray("additional")?.map { it.asString }.orEmpty(),
                scriptResult = json.get("scriptResult")?.takeUnless { it.isJsonNull }?.asString,
                userAgent = json.get("userAgent")?.takeUnless { it.isJsonNull }?.asString,
            )
        }.getOrNull()
    }

    /** Loads [url] and returns what [script] evaluates to, or null. */
    fun evaluate(url: String, script: String, timeoutMs: Long = 30_000L): String? =
        resolve(url, script = script, timeoutMs = timeoutMs)?.scriptResult
}
