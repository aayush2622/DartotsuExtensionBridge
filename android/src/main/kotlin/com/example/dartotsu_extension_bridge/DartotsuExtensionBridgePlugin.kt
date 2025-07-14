package com.example.dartotsu_extension_bridge

import android.app.Application
import android.content.Context
import eu.kanade.tachiyomi.network.NetworkHelper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import kotlinx.serialization.json.Json
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingletonFactory

/** DartotsuExtensionBridgePlugin */
class DartotsuExtensionBridgePlugin : FlutterPlugin {
    private lateinit var context: Context
    private lateinit var aniyomiChannel: MethodChannel
    private lateinit var aniyomiBridge: AniyomiBridge

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        Injekt.addSingletonFactory<Application> { context as Application }
        Injekt.addSingletonFactory { NetworkHelper(context) }
        Injekt.addSingletonFactory { NetworkHelper(context).client }
        Injekt.addSingletonFactory { Json { ignoreUnknownKeys = true ;explicitNulls = false }}
        Injekt.addSingletonFactory { AniyomiExtensionManager(context) }
        aniyomiBridge = AniyomiBridge(context)
        aniyomiChannel = MethodChannel(binding.binaryMessenger, "aniyomiExtensionBridge")
        aniyomiChannel.setMethodCallHandler(aniyomiBridge)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        aniyomiChannel.setMethodCallHandler(null)
    }
}