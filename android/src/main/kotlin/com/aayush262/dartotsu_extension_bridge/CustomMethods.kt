package com.aayush262.dartotsu_extension_bridge

import android.os.Handler
import android.os.Looper
import com.aayush262.dartotsu_extension_bridge.common.BridgeCallbacks
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class CustomMethods(var networkChannel: MethodChannel) : BridgeCallbacks {
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Calls [method] on the Dart side and waits up to [timeoutMs] for the
     * reply. Method channel replies arrive on the main thread, so waiting
     * there would deadlock; such calls return null at once.
     */
    private fun invokeBlocking(method: String, args: Map<String, Any?>, timeoutMs: Long): Any? {
        if (Looper.myLooper() == Looper.getMainLooper()) return null

        val latch = CountDownLatch(1)
        var value: Any? = null

        mainHandler.post {
            networkChannel.invokeMethod(
                method,
                args,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        value = result
                        latch.countDown()
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        latch.countDown()
                    }

                    override fun notImplemented() {
                        latch.countDown()
                    }
                }
            )
        }

        latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        return value
    }

    override fun getCookies(url: String): String? =
        invokeBlocking("getCookies", mapOf("url" to url), 500) as? String

    override fun setCookies(url: String, cookies: List<String>) {
        mainHandler.post {
            networkChannel.invokeMethod(
                "setCookies",
                mapOf(
                    "url" to url,
                    "cookies" to cookies
                )
            )
        }
    }

    override fun getUserAgent(): String? =
        invokeBlocking("getUserAgent", emptyMap(), 500) as? String

    override fun solveCloudflare(url: String): Boolean = solveCloudflare(url, false)

    override fun solveCloudflare(url: String, retried: Boolean): Boolean =
        invokeBlocking("solveCloudflare", mapOf("url" to url, "retried" to retried), SLOW_TIMEOUT_MS) == true

    override fun webView(request: String): String? =
        invokeBlocking("webView", mapOf("request" to request), SLOW_TIMEOUT_MS) as? String

    override fun log(level: String, message: String) {
        Logger.log("[EXT] $message")
    }

    private companion object {
        const val SLOW_TIMEOUT_MS = 6 * 60 * 1000L
    }
}
