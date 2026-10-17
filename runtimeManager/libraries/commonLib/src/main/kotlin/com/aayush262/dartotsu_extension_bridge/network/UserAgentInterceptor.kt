package com.aayush262.dartotsu_extension_bridge.network

import okhttp3.Interceptor
import okhttp3.Response

/** Gives requests without a User-Agent the app's one. */
class UserAgentInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        if (!request.header("User-Agent").isNullOrBlank()) return chain.proceed(request)
        return chain.proceed(request.newBuilder().header("User-Agent", Network.userAgent).build())
    }
}
