package com.aayush262.dartotsu_extension_bridge

import com.ryan.cloudstream_bridge.cloudstream.CloudStreamPluginBridge
import android.app.Application
import com.aayush262.dartotsu_extension_bridge.aniyomi.AniyomiBridge
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
/** DartotsuExtensionBridgePlugin */
class DartotsuExtensionBridgePlugin : FlutterPlugin, ActivityAware {

    private lateinit var aniyomiBridge: AniyomiBridge

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {

        CloudStreamPluginBridge.onAttachedToEngine(binding)

        AniyomiBridge().apply {
            aniyomiBridge = this
            attach(binding)
        }

        Logger.log("Plugin attached to engine", LogLevel.INFO)
        println("Plugin attached to engine")

    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        aniyomiBridge.detach()
        CloudStreamPluginBridge.onDetachedFromEngine(binding)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        CloudStreamPluginBridge.onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        CloudStreamPluginBridge.onDetachedFromActivityForConfigChanges()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        CloudStreamPluginBridge.onReattachedToActivityForConfigChanges(binding)
    }

    override fun onDetachedFromActivity() {
        CloudStreamPluginBridge.onDetachedFromActivity()
    }

}
