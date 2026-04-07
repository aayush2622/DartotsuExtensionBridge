package com.aayush262.dartotsu_extension_bridge

import kotlinx.coroutines.*

object Logger {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @JvmStatic
    fun log(message: String, level: LogLevel = LogLevel.INFO) {
        scope.launch {
            customAniyomiMethods?.log(level.name, message)
                ?: println("[${level.name}] $message")
        }
    }
    @JvmStatic
    fun log(message: String,throwable: Throwable, level: LogLevel = LogLevel.ERROR) {
        scope.launch {
            customAniyomiMethods?.log(level.name, "$message\n${throwable.stackTraceToString()}")
                ?: println("[${level.name}] $message\n${throwable.stackTraceToString()}")
        }
    }


}

enum class LogLevel {
    ERROR, WARNING, INFO, DEBUG
}