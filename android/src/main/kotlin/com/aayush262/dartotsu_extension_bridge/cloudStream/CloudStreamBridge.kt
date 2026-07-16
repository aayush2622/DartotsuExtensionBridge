package com.aayush262.dartotsu_extension_bridge.cloudStream

import android.content.Context
import com.aayush262.dartotsu_extension_bridge.Handler
import com.aayush262.dartotsu_extension_bridge.CustomMethods
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
class CloudStreamBridge(var context: Context, var customMethods: CustomMethods) {
    private lateinit var channel: MethodChannel
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            binding.binaryMessenger, "cloudStreamExtensionBridge"
        ).apply {
            val className = "com.aayush262.dartotsu_extension_bridge.CloudStreamExtensionApi"
            val packageName = "com.aayush262.dartotsu_extension_bridge.cloudStream_plugin"
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