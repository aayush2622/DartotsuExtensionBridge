package com.aayush262.dartotsu_extension_bridge

object CommonDesktopApi {
    lateinit var rootDir: String

    fun init(rootDirectory: String) {
        rootDir = rootDirectory
    }
}