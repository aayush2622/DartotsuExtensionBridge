package com.aayush262.dartotsu_extension_bridge

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

object Logger {



    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)



    fun log(message: String, level: LogLevel = LogLevel.INFO) {


        mainScope.launch {
            // For now, just print the log message. You can replace this with a more sophisticated logging mechanism if needed.
            println("[${level.name}] $message")
        }
    }
}

enum class LogLevel {
    ERROR, WARNING, INFO, DEBUG
}