package com.aayush262.dartotsu_extension_bridge.tsundoku

import android.content.Context
import com.aayush262.dartotsu_extension_bridge.Handler
import com.aayush262.dartotsu_extension_bridge.CustomMethods
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class TsundokuBridge(var context: Context, var customMethods: CustomMethods) {

    private lateinit var channel: MethodChannel
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            binding.binaryMessenger, "tsundokuExtensionBridge"
        ).apply {
            val className = "com.aayush262.dartotsu_extension_bridge.TsundokuExtensionApi"
            val packageName = "com.aayush262.dartotsu_extension_bridge.tsundoku_plugin"
            setMethodCallHandler(
                Handler(
                    context, scope, className, packageName, customMethods
                )
            )
        }
    }

    fun detach() {
        channel.setMethodCallHandler(null)
    }

}