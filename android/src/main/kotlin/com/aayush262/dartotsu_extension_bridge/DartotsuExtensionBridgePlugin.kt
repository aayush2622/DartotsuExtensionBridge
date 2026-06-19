package com.aayush262.dartotsu_extension_bridge

import com.aayush262.dartotsu_extension_bridge.aniyomi.AniyomiBridge
import com.aayush262.dartotsu_extension_bridge.CustomMethods
import com.aayush262.dartotsu_extension_bridge.cloudStream.CloudStreamBridge
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/** DartotsuExtensionBridgePlugin */
class DartotsuExtensionBridgePlugin : FlutterPlugin {

    private lateinit var aniyomiBridge: AniyomiBridge
    private lateinit var cloudStreamBridge: CloudStreamBridge

    private lateinit var loggerChannel: MethodChannel
    private lateinit var networkChannel: MethodChannel
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        loggerChannel = MethodChannel(
            binding.binaryMessenger, "flutterKotlinBridge.logger"
        )
        networkChannel = MethodChannel(
            binding.binaryMessenger, "flutterKotlinBridge.network"
        )

        Logger.init(loggerChannel)
        val customMethods = CustomMethods(networkChannel)

        aniyomiBridge = AniyomiBridge(binding.applicationContext, customMethods).apply {
            attach(binding)
        }
        cloudStreamBridge = CloudStreamBridge(binding.applicationContext, customMethods).apply {
            attach(binding)
        }
        Logger.log("Plugin attached to engine", LogLevel.INFO)
        println("Plugin attached to engine")

    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        aniyomiBridge.detach()
        cloudStreamBridge.detach()
        loggerChannel.setMethodCallHandler(null)
        networkChannel.setMethodCallHandler(null)
    }
}
