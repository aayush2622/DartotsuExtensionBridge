package com.aayush262.dartotsu_extension_bridge

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

object Logger {

    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun log(message: String, level: LogLevel = LogLevel.INFO) {
        mainScope.launch {
            customAniyomiMethods?.log(level.name, message) ?: Log.d("ExtensionLogger", "[${level.name}] $message")
        }
    }
}

enum class LogLevel {
    ERROR, WARNING, INFO, DEBUG
}