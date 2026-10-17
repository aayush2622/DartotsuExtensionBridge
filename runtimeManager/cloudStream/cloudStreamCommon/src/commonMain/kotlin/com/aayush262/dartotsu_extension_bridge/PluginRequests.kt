package com.aayush262.dartotsu_extension_bridge

import com.aayush262.dartotsu_extension_bridge.network.Network
import com.lagradost.nicehttp.Requests
import java.util.Collections
import java.util.WeakHashMap

/**
 * Puts the shared network (cookies, Cloudflare, User-Agent, DoH, proxy) on
 * `Requests` instances an extension builds itself instead of using `app`.
 * Desktop's `BytecodeEditor` calls [adopt] right after each construction.
 */
object PluginRequests {
    private val adopted = Collections.newSetFromMap(WeakHashMap<Requests, Boolean>())

    @JvmStatic
    fun adopt(requests: Requests) {
        synchronized(adopted) { adopted.add(requests) }
        apply(requests)
    }

    fun refresh() {
        val all = synchronized(adopted) { adopted.toList() }
        all.forEach(::apply)
    }

    private fun apply(requests: Requests) {
        runCatching {
            requests.baseClient = Network.applyTo(requests.baseClient.newBuilder()).build()
        }
    }
}
