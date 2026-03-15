package com.aayush262.dartotsu_extension_bridge.aniyomi

import android.content.Context
import dalvik.system.DexClassLoader
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import com.aayush262.dartotsu_extension_bridge.LogLevel
import com.aayush262.dartotsu_extension_bridge.Logger

class AniyomiBridge(private val context: Context) {

    private lateinit var channel: MethodChannel
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var api: ExtensionApi? = null

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            binding.binaryMessenger,
            "aniyomiExtensionBridge"
        ).apply {
            setMethodCallHandler(Handler())
        }

        loadApi(binding.applicationContext)
    }

    fun detach() {
        channel.setMethodCallHandler(null)
    }

    /**
     * Loads the Extension API implementation from the plugin APK.
     */
    private fun loadApi(context: Context) {
        try {

            val pluginPackage = "com.aayush262.dartotsu.aniyomi_plugin"

            val appInfo = context.packageManager
                .getApplicationInfo(pluginPackage, 0)

            val apkPath = appInfo.sourceDir

            val classLoader = DexClassLoader(
                apkPath,
                context.codeCacheDir.absolutePath,
                null,
                context.classLoader
            )

            val clazz = classLoader.loadClass(
                "com.aayush262.dartotsu_extension_bridge.AniyomiExtensionApi"
            )

            val instance = clazz.getDeclaredConstructor().newInstance()

            api = instance as ExtensionApi

            Logger.log("Extension API loaded successfully", LogLevel.INFO)

        } catch (e: Throwable) {
            Logger.log(
                "Failed to load Extension API: ${e.stackTraceToString()}",
                LogLevel.ERROR
            )
        }
    }

    private inner class Handler : MethodChannel.MethodCallHandler {

        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {

            val api = api
                ?: return result.error(
                    "API_NOT_LOADED",
                    "Extension API not loaded",
                    null
                )

            runCatching {

                when (call.method) {

                    "getInstalledAnimeExtensions" ->
                        launch(call, result) {
                            api.getInstalledAnimeExtensions(call.arguments as String?)
                        }

                    "getInstalledMangaExtensions" ->
                        launch(call, result) {
                            api.getInstalledMangaExtensions()
                        }

                    "getPopular" ->
                        launch(call, result) {
                            val args = call.arguments as Map<*, *>

                            api.getPopular(
                                args["sourceId"] as String,
                                args["isAnime"] as Boolean,
                                args["page"] as Int
                            )
                        }

                    "getLatestUpdates" ->
                        launch(call, result) {
                            val args = call.arguments as Map<*, *>

                            api.getLatestUpdates(
                                args["sourceId"] as String,
                                args["isAnime"] as Boolean,
                                args["page"] as Int
                            )
                        }

                    "search" ->
                        launch(call, result) {
                            val args = call.arguments as Map<*, *>

                            api.search(
                                args["sourceId"] as String,
                                args["isAnime"] as Boolean,
                                args["query"] as String,
                                args["page"] as Int
                            )
                        }

                    "getDetail" ->
                        launch(call, result) {
                            val args = call.arguments as Map<*, *>

                            api.getDetail(
                                args["sourceId"] as String,
                                args["isAnime"] as Boolean,
                                args["media"] as Map<String, Any?>
                            )
                        }

                    "getVideoList" ->
                        launch(call, result) {
                            val args = call.arguments as Map<*, *>

                            api.getVideoList(
                                args["sourceId"] as String,
                                args["isAnime"] as Boolean,
                                args["episode"] as Map<String, Any?>
                            )
                        }

                    "getPageList" ->
                        launch(call, result) {
                            val args = call.arguments as Map<*, *>

                            api.getPageList(
                                args["sourceId"] as String,
                                args["isAnime"] as Boolean,
                                args["episode"] as Map<String, Any?>
                            )
                        }

                    "getPreference" ->
                        launch(call, result) {
                            val args = call.arguments as Map<*, *>

                            api.getPreference(
                                args["sourceId"] as String,
                                args["isAnime"] as Boolean
                            )
                        }

                    "saveSourcePreference" ->
                        launch(call, result) {
                            val args = call.arguments as Map<*, *>

                            api.saveSourcePreference(
                                args["sourceId"] as String,
                                args["key"] as String,
                                args["action"] as? String ?: "change",
                                args["value"]
                            )
                        }

                    else -> result.notImplemented()
                }

            }.onFailure {

                Logger.log("Bad method call $it", LogLevel.INFO)

                result.error("INVALID_ARGS", it.message, null)
            }
        }
    }

    private fun launch(
        call: MethodCall,
        result: MethodChannel.Result,
        block: suspend () -> Any?
    ) {
        scope.launch {

            runCatching { block() }

                .onSuccess {
                    withContext(Dispatchers.Main) {
                        result.success(it)
                    }
                }

                .onFailure {

                    Logger.log(
                        "Error for [${call.method}]: $it",
                        LogLevel.ERROR
                    )

                    withContext(Dispatchers.Main) {
                        result.error("ERROR", it.message, null)
                    }
                }
        }
    }
}