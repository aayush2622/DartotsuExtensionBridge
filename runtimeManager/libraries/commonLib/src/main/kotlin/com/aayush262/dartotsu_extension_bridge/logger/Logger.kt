package com.aayush262.dartotsu_extension_bridge.logger

import com.aayush262.dartotsu_extension_bridge.customMethods
import kotlinx.coroutines.*

object Logger {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @JvmStatic
    fun log(message: String, level: LogLevel = LogLevel.INFO):Int {
        scope.launch {
            customMethods?.log(level.name, message)
                ?: println("[${level.name}] $message")
        }
        return 1
    }
    @JvmStatic
    fun log(message: String,throwable: Throwable, level: LogLevel = LogLevel.ERROR) {
        scope.launch {
            customMethods?.log(level.name, "$message\n${throwable.stackTraceToString()}")
                ?: println("[${level.name}] $message\n${throwable.stackTraceToString()}")
        }
    }


}

enum class LogLevel {
    ERROR, WARNING, INFO, DEBUG
}