package com.aayush262.dartotsu_extension_bridge.aniyomi

import android.os.Handler
import android.os.Looper
import com.aayush262.dartotsu_extension_bridge.Logger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class CustomAniyomiMethods(var networkChannel: MethodChannel) : CustomMethods {
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun getCookies(url: String): String? {
        val latch = CountDownLatch(1)
        var resultHeader: String? = null
        mainHandler.post {
            networkChannel.invokeMethod(
                "getCookies",
                url,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val map = result as? Map<*, *>
                        resultHeader = map
                            ?.entries
                            ?.joinToString("; ") { "${it.key}=${it.value}" }
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
        latch.await(500, TimeUnit.MILLISECONDS)
        return resultHeader
    }

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

    override fun log(level: String, message: String) {
        Logger.log("[EXT] $message")
    }
}