package com.aayush262.dartotsu_extension_bridge.aniyomi

import android.annotation.SuppressLint
import android.content.Context
import com.aayush262.dartotsu_extension_bridge.ExtensionApi
import dalvik.system.DexClassLoader
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import com.aayush262.dartotsu_extension_bridge.LogLevel
import com.aayush262.dartotsu_extension_bridge.Logger
import dalvik.system.BaseDexClassLoader
import java.io.File

class AniyomiBridge(var context: Context) {
    private lateinit var loggerChannel: MethodChannel
    private lateinit var networkChannel: MethodChannel
    private lateinit var channel: MethodChannel
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var api: ExtensionApi? = null
    private val apiReady = CompletableDeferred<ExtensionApi>()
    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            binding.binaryMessenger,
            "aniyomiExtensionBridge"
        ).apply {
            setMethodCallHandler(Handler())
        }
        networkChannel = MethodChannel(
            binding.binaryMessenger,
            "flutterKotlinBridge.network"
        ).apply {
            setMethodCallHandler(NetworkHandler())
        }

        loggerChannel = MethodChannel(
            binding.binaryMessenger,
            "flutterKotlinBridge.logger"
        )

        Logger.init(loggerChannel)
    }

    fun detach() {
        channel.setMethodCallHandler(null)
        networkChannel.setMethodCallHandler(null)
        loggerChannel.setMethodCallHandler(null)
    }
    @SuppressLint("SetWorldReadable")
    private fun loadApiFromPath(path: String, hasUpdate: Boolean) {

        if (api != null) {
            Logger.log("API already initialized, skipping load", LogLevel.INFO)
            return
        }

        try {
            val externalFile = File(path)

            if (!externalFile.exists()) {
                Logger.log("Plugin not found at $path", LogLevel.ERROR)
                return
            }

            Logger.log("External plugin: ${externalFile.absolutePath}", LogLevel.INFO)

            val privateDir = File(context.filesDir, "plugins")
            if (!privateDir.exists()) privateDir.mkdirs()

            val dst = File(privateDir, externalFile.name)

            if (!hasUpdate && dst.exists()) {
                Logger.log("Plugin already exists, skipping copy", LogLevel.INFO)
            } else {
                Logger.log("Copying plugin to internal storage...", LogLevel.INFO)

                val tmp = File(privateDir, "${externalFile.name}.tmp")

                tmp.outputStream().use { out ->
                    externalFile.inputStream().use { input ->
                        input.copyTo(out)
                    }
                }

                if (!tmp.renameTo(dst)) {
                    tmp.delete()
                    throw RuntimeException("Failed to finalize ${dst.name}")
                }

                Logger.log("Plugin copied/updated", LogLevel.INFO)
            }

            dst.setReadable(true, false)
            dst.setWritable(false, false)
            dst.setExecutable(false)

            Logger.log("Internal plugin ready: ${dst.absolutePath}", LogLevel.INFO)
            val optimizedDir = File(context.codeCacheDir, "plugin_opt")
            if (!optimizedDir.exists()) optimizedDir.mkdirs()

            val classLoader = context.classLoader

            val pathListField = BaseDexClassLoader::class.java
                .getDeclaredField("pathList")
                .apply { isAccessible = true }

            val pathList = pathListField[classLoader]

            val addDexPath = pathList.javaClass
                .getDeclaredMethod(
                    "addDexPath",
                    String::class.java,
                    File::class.java
                )
                .apply { isAccessible = true }

            Logger.log("Injecting dex...", LogLevel.INFO)

            addDexPath.invoke(
                pathList,
                dst.absolutePath,
                optimizedDir
            )

            Logger.log("Dex injected successfully", LogLevel.INFO)

            val clazz = classLoader.loadClass(
                "com.aayush262.dartotsu_extension_bridge.AniyomiExtensionApi"
            )

            val instance = clazz.getDeclaredConstructor().newInstance()

            api = instance as ExtensionApi

            Logger.log("Extension API loaded successfully", LogLevel.INFO)

            api?.initialize(context)

            (instance as AniyomiCustomMethods).initialize(CustomAniyomiMethods(networkChannel)).apply {
                Logger.log("Custom methods initialized", LogLevel.INFO)
            }

            apiReady.complete(api!!)
        } catch (e: Throwable) {
            Logger.log(
                "Failed to load Extension API: ${e.stackTraceToString()}",
                LogLevel.ERROR
            )
        }
    }

    @Suppress("UNUSED")
    private fun loadApi(context: Context) {
        // for local test
        try {

            val pluginPackage =
                "com.aayush262.dartotsu.aniyomi_plugin"

            val appInfo =
                context.packageManager.getApplicationInfo(
                    pluginPackage,
                    0
                )

            val apkPath = appInfo.sourceDir
            val apkFile = File(apkPath)

            val classLoader = context.classLoader

            val pathListField = BaseDexClassLoader::class.java.getDeclaredField("pathList")
                .apply { isAccessible = true }
            val pathList = pathListField[classLoader]!!
            val addDexPath =
                pathList.javaClass.getDeclaredMethod(
                    "addDexPath",
                    String::class.java,
                    File::class.java
                )
                    .apply { isAccessible = true }
            addDexPath.invoke(pathList, apkFile.absolutePath, null)

            val clazz = classLoader.loadClass(
                "com.aayush262.dartotsu_extension_bridge.AniyomiExtensionApi"
            )

            val instance =
                clazz.getDeclaredConstructor().newInstance()

            api = instance as ExtensionApi

            Logger.log("Extension API loaded successfully", LogLevel.INFO)

            api?.initialize(context)

            (instance as AniyomiCustomMethods).initialize(CustomAniyomiMethods(networkChannel)).apply {
                Logger.log("Custom methods initialized", LogLevel.INFO)
            }

            apiReady.complete(api!!)
        } catch (e: Throwable) {
            Logger.log(
                "Failed to load Extension API: ${e.stackTraceToString()}",
                LogLevel.ERROR
            )
        }
    }
    private inner class Handler : MethodChannel.MethodCallHandler {
        @Suppress("UNCHECKED_CAST")
        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            if (call.method == "loadPlugin") {
                runCatching {
                    val args = call.arguments as Map<*, *>

                    val path = args["path"] as String
                    val hasUpdate = args["hasUpdate"] as? Boolean ?: false

                    loadApiFromPath(path, hasUpdate)
                    //loadApi(context)
                    result.success(null)
                }.onFailure {
                    result.error("LOAD_FAILED", it.message, null)
                }
                return
            }

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
                            api.getInstalledMangaExtensions( call.arguments as String?)
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
    private inner class NetworkHandler : MethodChannel.MethodCallHandler {
        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "initClient" -> {
                    scope.launch {
                        val args = call.arguments as? Map<*, *>
                            ?: return@launch result.error(
                                "INVALID_ARGUMENTS",
                                "Expected a map",
                                null
                            )

                        try {
                            apiReady.await()
                        } catch (e: Throwable) {
                            withContext(Dispatchers.Main) {
                                result.error("API_ERROR", e.message, null)
                            }
                            return@launch
                        }

                        runCatching {
                            (api as AniyomiCustomMethods).initClient(args)
                            Logger.log("Network client initialized successfully", LogLevel.INFO)
                        }.onFailure {
                            Logger.log("initClient failed: ${it.stackTraceToString()}", LogLevel.ERROR)
                            withContext(Dispatchers.Main) {
                                result.error("INIT_FAILED", it.message, null)
                            }
                            return@launch
                        }

                        withContext(Dispatchers.Main) {
                            result.success(null)
                        }
                    }
                }

                else -> result.notImplemented()
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
                        "Error for [${call.method}]: ${it.message}\n${it.stackTraceToString()}",
                        LogLevel.ERROR
                    )

                    withContext(Dispatchers.Main) {
                        result.error("ERROR", it.message, null)
                    }
                }
        }
    }
}