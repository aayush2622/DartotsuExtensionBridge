package com.lagradost.api

import com.aayush262.dartotsu_extension_bridge.logger.Logger

object Log {
    fun d(tag: String, message: String) {
         Logger.log( message)
    }

    fun i(tag: String, message: String) {
        Logger.log( message)
    }

    fun w(tag: String, message: String) {
        Logger.log( message)
    }

    fun e(tag: String, message: String) {
        Logger.log( message)
    }
}
