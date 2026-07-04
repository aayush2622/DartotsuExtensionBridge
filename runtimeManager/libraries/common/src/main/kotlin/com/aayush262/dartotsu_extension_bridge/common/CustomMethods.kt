package com.aayush262.dartotsu_extension_bridge.common

import com.aayush262.dartotsu_extension_bridge.CommonApi

interface ExtensionBridgeApi {
    fun initialize(customMethods: BridgeCallbacks){
        CommonApi.init(customMethods)
    }
    fun initClient(data: String)
}

interface BridgeCallbacks {
    fun getCookies(url: String): String?
    fun setCookies(url: String, cookies: List<String>)
    fun log(level: String, message: String)
}