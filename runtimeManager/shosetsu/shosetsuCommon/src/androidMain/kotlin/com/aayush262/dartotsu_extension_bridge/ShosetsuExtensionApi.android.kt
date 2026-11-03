package com.aayush262.dartotsu_extension_bridge

import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi

actual object ShosetsuPlatformInit {
    actual fun initializeAndroid(context: Any) {}

    actual fun initializeDesktop(basePath: String, api: ExtensionBridgeApi) {}
}
