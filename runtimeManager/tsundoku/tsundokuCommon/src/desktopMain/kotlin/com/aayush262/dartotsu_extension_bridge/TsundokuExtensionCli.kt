package com.aayush262.dartotsu_extension_bridge


object Main {
    @JvmStatic
    fun main(args: Array<String>) {
        Server.run( TsundokuExtensionApi())
    }
}
