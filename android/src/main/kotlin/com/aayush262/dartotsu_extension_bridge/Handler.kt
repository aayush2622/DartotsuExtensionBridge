package com.aayush262.dartotsu_extension_bridge

import android.annotation.SuppressLint
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ApplicationInfo
import android.content.res.AssetManager
import android.os.Build
import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import dalvik.system.DexClassLoader
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.zip.ZipFile


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
                val debug = args["debug"] as? Boolean ?: false

                if (debug) {
                    loadApi(context)
                } else {
                    loadApiFromPath(path)
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

                "getInstalledNovelExtensions" -> launch(call, result) {
                    api.getInstalledNovelExtensions(call.arguments as String?)
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
                        args["sourceId"] as String,
                        args["isAnime"] as Boolean,
                        args["query"] as String,
                        args["page"] as Int,
                        args["filters"] as? String ?: "[]",
                    )
                }

                "getFilterList" -> launch(call, result) {
                    val args = call.arguments as Map<*, *>

                    api.getFilterList(
                        args["sourceId"] as String, args["isAnime"] as Boolean
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

                "getNovelContent" -> launch (call, result) {
                    val args = call.arguments as Map<*, *>

                    api.getNovelContent(
                        args["sourceId"] as String,  args["episode"] as String
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

            val apk = File(appInfo.sourceDir)
            val classLoader = createPluginLoader(apk)
            initializeOkHttpPlatform(classLoader, context, apk)

            val clazz = classLoader.loadClass(apiClassName)

            api = clazz.getDeclaredConstructor()
                .newInstance() as ExtensionApi

            api!!.initializeAndroid(context)

            (api as ExtensionBridgeApi).initialize(customMethods).apply {
                Logger.log("Custom methods initialized", LogLevel.INFO)
            }

            apiReady.complete(api!!)

        } catch (e: Throwable) {
            api = null
            apiReady.completeExceptionally(e)

            Logger.log(
                "Failed to load Extension API: ${e.stackTraceToString()}",
                LogLevel.ERROR
            )
        }
    }
    // A plugin APK is loaded by hand via DexClassLoader rather than installed
    // as a real package, so the OS never instantiates its merged
    // androidx.startup ContentProvider - any androidx.startup Initializer the
    // plugin bundles (e.g. okhttp-android's PlatformInitializer, which sets
    // the Context AndroidPlatform.applicationContext needs) never runs,
    // leaving its networking failing with "Platform applicationContext not
    // initialized". Run it ourselves against the plugin's own classloader.
    //
    // okhttp-android ships its public suffix list as an Android asset
    // (assets/PublicSuffixDatabase.list), read via context.assets - the host
    // app's own AssetManager only sees the host APK's assets, not this
    // dynamically loaded plugin's, so that lookup needs an AssetManager
    // pointed at the plugin file itself (same trick as CloudStream's
    // pluginResources()).
    private fun initializeOkHttpPlatform(classLoader: ClassLoader, context: Context, apk: File) {
        try {
            val initializerClass =
                classLoader.loadClass("okhttp3.internal.platform.PlatformInitializer")
            val instance = initializerClass.getDeclaredConstructor().newInstance()
            val create = initializerClass.getMethod("create", Context::class.java)
            create.invoke(instance, pluginAssetsContext(context, apk))
        } catch (_: ClassNotFoundException) {
            // Plugin doesn't bundle okhttp-android - nothing to do.
        } catch (e: Throwable) {
            Logger.log("OkHttp platform init failed: ${e.message}", LogLevel.INFO)
        }
    }

    private fun pluginAssetsContext(context: Context, apk: File): Context {
        val assets = AssetManager::class.java.getDeclaredConstructor().newInstance()
        AssetManager::class.java.getMethod("addAssetPath", String::class.java)
            .invoke(assets, apk.absolutePath)

        return object : ContextWrapper(context) {
            override fun getAssets(): AssetManager = assets
        }
    }

    private fun createPluginLoader(apk: File): ClassLoader {
        val libDir = extractNativeLibraries(apk)
        val optimizedDir = File(context.codeCacheDir, "plugin_opt")
        optimizedDir.mkdirs()
        return DexClassLoader(
            apk.absolutePath,
            optimizedDir.absolutePath,
            libDir.absolutePath,
            context.classLoader,
        )
    }

    private fun extractNativeLibraries(apkFile: File): File {
        val abi = Build.SUPPORTED_ABIS.first()
        val outDir = File(context.codeCacheDir, "plugin_libs/${apkFile.nameWithoutExtension}").apply {
            mkdirs()
        }

        ZipFile(apkFile).use { zip ->
            zip.entries().asSequence()
                .filter {
                    it.name.startsWith("lib/$abi/") &&
                            it.name.endsWith(".so")
                }
                .forEach { entry ->
                    val out = File(outDir, entry.name.substringAfterLast('/'))

                    if (!out.exists() || out.length() != entry.size) {
                        zip.getInputStream(entry).use { input ->
                            out.outputStream().use(input::copyTo)
                        }
                        out.setReadable(true)
                        out.setExecutable(true)
                    }
                }
        }
        return outDir
    }
    @SuppressLint("SetWorldReadable")
    private fun loadApiFromPath(path: String) {

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
            val shouldCopy =
                !dst.exists() ||
                        externalFile.length() != dst.length() ||
                        externalFile.lastModified() != dst.lastModified()

            if (shouldCopy) {
                Logger.log("Copying plugin", LogLevel.INFO)

                val tmp = File(privateDir, "${externalFile.name}.tmp")

                externalFile.inputStream().use { input ->
                    tmp.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }

                tmp.setLastModified(externalFile.lastModified())

                if (!tmp.renameTo(dst)) {
                    tmp.delete()
                    throw RuntimeException("Failed to replace plugin")
                }
            } else {
                Logger.log("Plugin unchanged", LogLevel.INFO)
            }

            dst.setReadable(true, false)
            dst.setWritable(false, false)
            dst.setExecutable(false)

            Logger.log("Internal plugin ready: ${dst.absolutePath}", LogLevel.INFO)
            Logger.log("Creating plugin class loader...", LogLevel.INFO)

            val classLoader = createPluginLoader(dst)
            initializeOkHttpPlatform(classLoader, context, dst)

            Logger.log("Plugin class loader ready", LogLevel.INFO)

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
            api = null
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