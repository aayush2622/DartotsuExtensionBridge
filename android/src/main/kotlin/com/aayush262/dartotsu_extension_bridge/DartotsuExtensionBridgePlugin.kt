package com.aayush262.dartotsu_extension_bridge

import android.app.Application
import android.content.Context
import android.util.Log
import com.aayush262.dartotsu_extension_bridge.aniyomi.AniyomiBridge
import com.aayush262.dartotsu_extension_bridge.aniyomi.AniyomiExtensionManager
import eu.kanade.tachiyomi.network.NetworkHelper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import kotlinx.serialization.json.Json
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingletonFactory
import uy.kohesive.injekt.api.get
const val TAG = "DartotsuExtensionBridge"
/** DartotsuExtensionBridgePlugin */
class DartotsuExtensionBridgePlugin : FlutterPlugin {

    private var aniyomiChannel: MethodChannel? = null
    private var flutterKotlinBridge: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "Plugin attached to engine")

        val appContext = binding.applicationContext
        val application = appContext as? Application
            ?: error("Application context is not an Application")

        initInjekt(application)

        flutterKotlinBridge = MethodChannel(
            binding.binaryMessenger,
            "flutterKotlinBridge"
        ).apply {
            setMethodCallHandler(FlutterKotlinBridge(this))
        }

        aniyomiChannel = MethodChannel(
            binding.binaryMessenger,
            "aniyomiExtensionBridge"
        ).apply {
            setMethodCallHandler(AniyomiBridge(appContext))
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterKotlinBridge?.setMethodCallHandler(null)
        aniyomiChannel?.setMethodCallHandler(null)

        flutterKotlinBridge = null
        aniyomiChannel = null
    }

    private fun initInjekt(application: Application) {
        Injekt.addSingletonFactory<Application> { application }
        Injekt.addSingletonFactory { NetworkHelper(application) }
        Injekt.addSingletonFactory { Injekt.get<NetworkHelper>().client }
        Injekt.addSingletonFactory {
            Json {
                ignoreUnknownKeys = true
                explicitNulls = false
            }
        }
        Injekt.addSingletonFactory { AniyomiExtensionManager(application) }
    }
}
