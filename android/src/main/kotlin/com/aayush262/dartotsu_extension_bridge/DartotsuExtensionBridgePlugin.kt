package com.aayush262.dartotsu_extension_bridge

import android.app.Application
import android.content.Context
import android.util.Log
import com.aayush262.dartotsu_extension_bridge.aniyomi.AniyomiBridge
import com.aayush262.dartotsu_extension_bridge.aniyomi.AniyomiExtensionManager
import com.aayush262.dartotsu_extension_bridge.network.FlutterNetworkBridge
import eu.kanade.tachiyomi.network.NetworkHelper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import kotlinx.serialization.json.Json
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingletonFactory
import uy.kohesive.injekt.api.get

/** DartotsuExtensionBridgePlugin */
class DartotsuExtensionBridgePlugin : FlutterPlugin {
    private lateinit var context: Context
    private lateinit var aniyomiChannel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d("PluginDebug", "Plugin attached to engine")
        context = binding.applicationContext
        FlutterNetworkBridge.init(binding.binaryMessenger)
        Injekt.addSingletonFactory<Application> { context as Application }
        Injekt.addSingletonFactory { NetworkHelper(context) }
        Injekt.addSingletonFactory { Injekt.get<NetworkHelper>().client }

        Injekt.addSingletonFactory { Json { ignoreUnknownKeys = true ;explicitNulls = false }}
        Injekt.addSingletonFactory { AniyomiExtensionManager(context) }
        aniyomiChannel = MethodChannel(binding.binaryMessenger, "aniyomiExtensionBridge")
        aniyomiChannel.setMethodCallHandler(AniyomiBridge(context))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        aniyomiChannel.setMethodCallHandler(null)
        FlutterNetworkBridge.detach()
    }

}
