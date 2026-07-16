package com.aayush262.dartotsu_extension_bridge

import android.annotation.SuppressLint
import android.content.Context
import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import dalvik.system.BaseDexClassLoader
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File


class Handler(
    private val context: Context,
    private val scope: CoroutineScope,
    private val apiClassName: String,
    private val apiPackageName: String,
    private val customMethods: CustomMethods

) : MethodChannel.MethodCallHandler {
    var api: ExtensionApi? = null
    val apiReady = CompletableDeferred<ExtensionApi>()

    @Suppress("UNCHECKED_CAST")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "loadPlugin") {
            runCatching {
                val args = call.arguments as Map<*, *>

                val path = args["path"] as String
                val hasUpdate = args["hasUpdate"] as? Boolean ?: false
                val debug = args["debug"] as? Boolean ?: false

                if (debug) {
                    loadApi(context)
                }else {
                    loadApiFromPath(path, hasUpdate)
                }
                result.success(null)
            }.onFailure {
                result.error("LOAD_FAILED", it.message, null)
            }
            return
        }

        val api = api ?: return result.error(
            "API_NOT_LOADED", "Extension API not loaded", null
        )

        runCatching {

            when (call.method) {
                "getInstalledAnimeExtensions" -> launch(call, result) {
                    api.getInstalledAnimeExtensions(call.arguments as String?)
                }

                "getInstalledMangaExtensions" -> launch(call, result) {
                    api.getInstalledMangaExtensions(call.arguments as String?)
                }

                "getPopular" -> launch(call, result) {
                    val args = call.arguments as Map<*, *>

                    api.getPopular(
                        args["sourceId"] as String, args["isAnime"] as Boolean, args["page"] as Int
                    )
                }

                "getLatestUpdates" -> launch(call, result) {
                    val args = call.arguments as Map<*, *>

                    api.getLatestUpdates(
                        args["sourceId"] as String, args["isAnime"] as Boolean, args["page"] as Int
                    )
                }

                "search" -> launch(call, result) {
                    val args = call.arguments as Map<*, *>

                    api.search(
                        args["sourceId"] as String, args["isAnime"] as Boolean, args["query"] as String, args["page"] as Int
                    )
                }

                "getDetail" -> launch(call, result) {
                    val args = call.arguments as Map<*, *>

                    api.getDetail(
                        args["sourceId"] as String, args["isAnime"] as Boolean, args["media"] as String
                    )
                }

                "getVideoList" -> launch(call, result) {
                    val args = call.arguments as Map<*, *>

                    api.getVideoList(
                        args["sourceId"] as String, args["isAnime"] as Boolean, args["episode"] as String
                    )
                }

                "getPageList" -> launch(call, result) {
                    val args = call.arguments as Map<*, *>

                    api.getPageList(
                        args["sourceId"] as String, args["isAnime"] as Boolean, args["episode"] as String
                    )
                }

                "getPreference" -> launch(call, result) {
                    val args = call.arguments as Map<*, *>

                    api.getPreference(
                        args["sourceId"] as String, args["isAnime"] as Boolean
                    )
                }

                "saveSourcePreference" -> launch(call, result) {
                    val args = call.arguments as Map<*, *>

                    api.saveSourcePreference(
                        args["sourceId"] as String, args["key"] as String, args["value"] as String?
                    )
                }

                "initClient" -> launch(call, result) {
                    val args = call.arguments as? String ?: return@launch result.error(
                        "INVALID_ARGUMENTS", "Expected a map", null
                    )

                    try {
                        apiReady.await()
                    } catch (e: Throwable) {
                        throw RuntimeException("API not ready: ${e.message}", e)
                    }
                    (api as ExtensionBridgeApi).initClient(args)
                    Logger.log("Network client initialized successfully", LogLevel.INFO)
                }

                else -> result.notImplemented()
            }

        }.onFailure {

            Logger.log("Bad method call $it", LogLevel.INFO)

            result.error("INVALID_ARGS", it.message, null)
        }
    }
    @Suppress("UNUSED")
    private fun loadApi(context: Context) {
        try {
            if (api != null) {
                Logger.log("API already initialized, skipping load", LogLevel.INFO)
                return
            }
            val appInfo = context.packageManager.getApplicationInfo(
                apiPackageName,
                0
            )

            val apkPath = appInfo.sourceDir

            val classLoader = context.classLoader

            val pathListField = BaseDexClassLoader::class.java
                .getDeclaredField("pathList")
                .apply { isAccessible = true }

            val pathList = pathListField.get(classLoader)

            val addDexPath = pathList.javaClass
                .getDeclaredMethod(
                    "addDexPath",
                    String::class.java,
                    File::class.java
                )
                .apply { isAccessible = true }

            val optimizedDir = File(context.codeCacheDir, "plugin_opt")
            optimizedDir.mkdirs()

            addDexPath.invoke(
                pathList,
                apkPath,
                optimizedDir
            )

            val clazz = classLoader.loadClass(apiClassName)

            api = clazz.getDeclaredConstructor()
                .newInstance() as ExtensionApi

            api!!.initializeAndroid(context)

            (api as ExtensionBridgeApi).initialize(customMethods).apply {
                Logger.log("Custom methods initialized", LogLevel.INFO)
            }

            apiReady.complete(api!!)

        } catch (e: Throwable) {
            apiReady.completeExceptionally(e)

            Logger.log(
                "Failed to load Extension API: ${e.stackTraceToString()}",
                LogLevel.ERROR
            )
        }
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

            val pathListField = BaseDexClassLoader::class.java.getDeclaredField("pathList").apply { isAccessible = true }

            val pathList = pathListField[classLoader]

            val addDexPath = pathList.javaClass.getDeclaredMethod(
                "addDexPath", String::class.java, File::class.java
            ).apply { isAccessible = true }

            Logger.log("Injecting dex...", LogLevel.INFO)

            addDexPath.invoke(
                pathList, dst.absolutePath, optimizedDir
            )

            Logger.log("Dex injected successfully", LogLevel.INFO)

            val clazz = classLoader.loadClass(apiClassName)

            val instance = clazz.getDeclaredConstructor().newInstance()

            api = instance as ExtensionApi

            Logger.log("Extension API loaded successfully", LogLevel.INFO)

            api?.initializeAndroid(context)

            (api as ExtensionBridgeApi).initialize(customMethods).apply {
                Logger.log("Custom methods initialized", LogLevel.INFO)
            }

            apiReady.complete(api!!)
        } catch (e: Throwable) {
            apiReady.completeExceptionally(e)
            Logger.log(
                "Failed to load Extension API: ${e.stackTraceToString()}", LogLevel.ERROR
            )
        }
    }

    private fun launch(
        call: MethodCall,
        result: MethodChannel.Result,
        block: suspend () -> Any?
    ) {
        scope.launch {
            try {
                val value = block()

                withContext(Dispatchers.Main) {
                    when (value) {
                        Unit -> result.success(null)
                        else -> result.success(value)
                    }
                }
            } catch (e: Throwable) {
                Logger.log(
                    "Error for [${call.method}]: ${e.message}\n${e.stackTraceToString()}",
                    LogLevel.ERROR
                )

                withContext(Dispatchers.Main) {
                    result.error("ERROR", e.message, null)
                }
            }
        }
    }
}