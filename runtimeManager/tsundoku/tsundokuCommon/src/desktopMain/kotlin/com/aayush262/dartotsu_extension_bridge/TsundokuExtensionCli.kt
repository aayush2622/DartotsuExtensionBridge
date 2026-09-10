package com.aayush262.dartotsu_extension_bridge


object Main {
    /** Used by the iOS embedded VM ([EmbeddedBridge]); desktop calls [main]. */
    @JvmStatic
    fun api(): ExtensionApi = TsundokuExtensionApi()

    @JvmStatic
    fun main(args: Array<String>) {
        Server.run(api())
    }
}
