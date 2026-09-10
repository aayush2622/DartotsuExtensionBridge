package com.aayush262.dartotsu_extension_bridge

object Main {
    /** Used by the iOS embedded VM ([EmbeddedBridge]); desktop calls [main]. */
    @JvmStatic
    fun api(): ExtensionApi = AniyomiExtensionApi()

    @JvmStatic
    fun main(args: Array<String>) {
        Server.run(api())
    }

    // Reflected into by the iOS EmbeddedBridge: one request in, envelope JSON
    // out, entirely within this JAR's own class loader.
    private val embeddedApi: ExtensionApi by lazy { api() }

    @JvmStatic
    fun handle(requestJson: String): String =
        Server.handleEmbedded(embeddedApi, requestJson)
}
