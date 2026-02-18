package com.aayush262.dartotsu_extension_bridge

import io.flutter.plugin.common.MethodChannel

object Logger {
    private lateinit var channel: MethodChannel

     fun init(channel: MethodChannel) {
        this.channel = channel
    }

     fun log(message: String) = channel.invokeMethod("log", message)

}