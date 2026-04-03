package com.aayush262.dartotsu_extension_bridge

import kotlinx.coroutines.*

object Logger {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun log(message: String, level: LogLevel = LogLevel.INFO) {
        scope.launch {
            customAniyomiMethods?.log(level.name, message)
                ?: println("[${level.name}] $message")
        }
    }
}

enum class LogLevel {
    ERROR, WARNING, INFO, DEBUG
}