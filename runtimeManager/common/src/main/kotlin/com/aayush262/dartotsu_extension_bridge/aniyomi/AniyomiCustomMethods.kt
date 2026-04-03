package com.aayush262.dartotsu_extension_bridge.aniyomi


/// This is a custom optional interface for flutter apps
interface AniyomiCustomMethods{
    fun initialize(customMethods: CustomMethods)

    fun initClient(data: Map<*, *>)
}

interface CustomMethods {
    fun getCookies(url: String):  String?
    fun setCookies(url: String, cookies: List<String>)
    fun log(level: String, message: String)
}