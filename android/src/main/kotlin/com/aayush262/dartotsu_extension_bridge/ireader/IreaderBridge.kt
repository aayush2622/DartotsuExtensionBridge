package com.aayush262.dartotsu_extension_bridge.ireader
import android.content.Context
import com.aayush262.dartotsu_extension_bridge.CustomMethods
import com.aayush262.dartotsu_extension_bridge.Handler
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class IreaderBridge(var context: Context, var customMethods: CustomMethods) {

    private lateinit var channel: MethodChannel
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            binding.binaryMessenger, "ireaderExtensionBridge"
        ).apply {
            val className = "com.aayush262.dartotsu_extension_bridge.IReaderExtensionApi"
            val packageName = "com.aayush262.dartotsu_extension_bridge.ireader_plugin"
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