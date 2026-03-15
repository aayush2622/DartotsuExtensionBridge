package com.aayush262.dartotsu_extension_bridge

import android.app.Application
import com.aayush262.dartotsu_extension_bridge.aniyomi.AniyomiBridge
import com.aayush262.dartotsu_extension_bridge.aniyomi.AniyomiExtensionManager
import com.aayush262.dartotsu_extension_bridge.aniyomi.PrintTest
import dalvik.system.DexClassLoader
import eu.kanade.tachiyomi.network.NetworkHelper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.serialization.json.Json
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingletonFactory
import uy.kohesive.injekt.api.get

/** DartotsuExtensionBridgePlugin */
class DartotsuExtensionBridgePlugin : FlutterPlugin {

    private lateinit var aniyomiBridge: AniyomiBridge
    private val flutterBridge = FlutterKotlinBridge()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {

        val application = binding.applicationContext as? Application
            ?: error("Application context is not an Application")

        initInjekt(application)
        
        flutterBridge.attach(binding)

        aniyomiBridge = AniyomiBridge(application).apply {
            attach(binding)
        }
        Logger.log("Plugin attached to engine", LogLevel.INFO)
        println("Plugin attached to engine")


        val pluginPackage = "com.aayush262.dartotsu.aniyomi_plugin"

        val appInfo = application.packageManager.getApplicationInfo(pluginPackage, 0)
        val apkPath = appInfo.sourceDir
        val loader = DexClassLoader(
            apkPath,
            application.codeCacheDir.absolutePath,
            null,
            application.classLoader
        )
        val clazz = loader.loadClass(
            "com.aayush262.dartotsu_extension_bridge.aniyomi.Tes"
        )
        print("Class loaded: ${clazz.name}")
        val instance = clazz.getDeclaredConstructor().newInstance()
        val plugin = instance as PrintTest
        plugin.printTest()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterBridge.detach()
        aniyomiBridge.detach()
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
