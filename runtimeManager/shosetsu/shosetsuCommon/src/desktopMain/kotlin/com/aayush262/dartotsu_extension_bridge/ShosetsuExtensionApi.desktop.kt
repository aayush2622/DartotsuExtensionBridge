package com.aayush262.dartotsu_extension_bridge

import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import java.io.File

actual object ShosetsuPlatformInit {
    actual fun initializeAndroid(context: Any) {}

    actual fun initializeDesktop(basePath: String, api: ExtensionBridgeApi) {
        val root = File(basePath).apply { mkdirs() }
        CommonDesktopApi.init(root.absolutePath)
        api.initialize(CustomMethods())
    }
}
