package com.aayush262.dartotsu_extension_bridge

import com.aayush262.dartotsu_extension_bridge.common.BridgeCallbacks
var customMethods: BridgeCallbacks? = null

object CommonApi {
    fun init(methods : BridgeCallbacks) {
        customMethods = methods
    }
}