package com.ryan.cloudstream_bridge.cloudstream

import android.annotation.SuppressLint
import androidx.preference.PreferenceManager
import android.content.Context
import android.util.Log
import com.lagradost.cloudstream3.AcraApplication
import com.lagradost.cloudstream3.APIHolder
import com.lagradost.cloudstream3.CloudStreamApp
import com.lagradost.cloudstream3.plugins.PluginManager
import com.lagradost.cloudstream3.utils.DataStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import android.app.Activity
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import com.lagradost.cloudstream3.utils.PREFERENCES_NAME
import kotlinx.coroutines.*
import java.io.File

@SuppressLint("StaticFieldLeak")
object CloudStreamPluginBridge : FlutterPlugin, ActivityAware {
    private const val TAG = "CloudStreamBridge"
    private lateinit var channel: MethodChannel
    private lateinit var videoStreamChannel: EventChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var videoStreamJob: Job? = null
    private var hasLoadedLocalPlugins = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "cloudstreamExtensionBridge")
        channel.setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }
        
        videoStreamChannel = EventChannel(binding.binaryMessenger, "cloudstreamExtensionBridge/videoStream")
        videoStreamChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val args = arguments as? Map<*, *> ?: return
                val apiName = args["apiName"] as? String ?: return
                val url = args["url"] as? String ?: return

                videoStreamJob?.cancel()
                videoStreamJob = scope.launch {
                    try {
                        val provider = findProvider(apiName)
                        if (provider == null) {
                            withContext(Dispatchers.Main) {
                                events?.error("NOT_FOUND", "Provider '$apiName' not found", null)
                                events?.endOfStream()
                            }
                            return@launch
                        }

                        CloudStreamSourceMethods(provider).loadLinksStream(url) { link ->
                            scope.launch(Dispatchers.Main) {
                                events?.success(link)
                            }
                        }
                        
                        withContext(Dispatchers.Main) {
                            events?.endOfStream()
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "videoStream failed", e)
                        withContext(Dispatchers.Main) {
                            events?.error("VIDEO_STREAM_FAILED", e.message, null)
                            events?.endOfStream()
                        }
                    }
                }
            }

            override fun onCancel(arguments: Any?) {
                videoStreamJob?.cancel()
                videoStreamJob = null
            }
        })

        initialize(context)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        videoStreamChannel.setStreamHandler(null)
        videoStreamJob?.cancel()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        if (activity !is androidx.appcompat.app.AppCompatActivity) {
            Log.w(TAG, "Attached activity is not AppCompatActivity. Some plugins may fail to load.")
        }
        if (!hasLoadedLocalPlugins) {
            hasLoadedLocalPlugins = true
            scope.launch {
                loadLocalPlugins(context)
            }
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private fun handleMethodCall(call: MethodCall, bridgeResult: Result) {
        when (call.method) {
            "initialize" -> {
                initialize(context)
                bridgeResult.success(null)
            }

            "loadLocalPlugins" -> scope.launch {
                try {
                    loadLocalPlugins(context)
                    withContext(Dispatchers.Main) { bridgeResult.success(null) }
                } catch (e: Exception) {
                    Log.e(TAG, "loadLocalPlugins failed", e)
                    withContext(Dispatchers.Main) { bridgeResult.error("LOAD_FAILED", e.message, null) }
                }
            }

            "getExtensionSettings" -> {
                val pluginName = call.argument<String>("pluginName")
                if (pluginName == null) {
                    bridgeResult.error("INVALID_ARGUMENT", "pluginName is required", null)
                    return
                }
                val allPrefs = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE).all
                val prefix = "$pluginName/"
                Log.i(TAG, "[KILAUD STREAM BRIDGE] getExtensionSettings for plugin: '$pluginName', prefix: '$prefix'")
                

                try {
                    val prefsDir = File(context.applicationInfo.dataDir, "shared_prefs")
                    if (prefsDir.exists() && prefsDir.isDirectory) {
                        val files = prefsDir.listFiles()
                        Log.i(TAG, "[KILAUD STREAM BRIDGE] --- START TOTAL PREFS DUMP ---")
                        Log.i(TAG, "[KILAUD STREAM BRIDGE] Total files found: ${files?.size ?: 0}")
                        files?.forEach { file ->
                            val prefsName = file.name.removeSuffix(".xml")
                            val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE).all
                            prefs.forEach { (key, value) ->
                                Log.i(TAG, "[KILAUD STREAM BRIDGE]   -> '$prefsName' | Key: '$key' | Value: '$value'")
                            }
                        }
                        Log.i(TAG, "[KILAUD STREAM BRIDGE] --- END TOTAL PREFS DUMP ---")
                    } else {
                        Log.w(TAG, "[KILAUD STREAM BRIDGE] shared_prefs directory not found at: ${prefsDir.absolutePath}")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "[KILAUD STREAM BRIDGE] Failed to dump all shared_prefs: ${e.message}")
                    Log.e(TAG, Log.getStackTraceString(e))
                }

                Log.i(TAG, "[KILAUD STREAM BRIDGE] Total preference keys in '$PREFERENCES_NAME': ${allPrefs.keys.size}")
                
                allPrefs.forEach { (key, value) ->
                    Log.i(TAG, "[KILAUD STREAM BRIDGE] Pref Dump -> Key: '$key', Value: '$value'")
                }
                
                val pluginSettings = mutableMapOf<String, Any?>()
                allPrefs.forEach { (key, value) ->
                    if (key.startsWith(prefix, ignoreCase = true)) {
                        val cleanKey = if (key.length > prefix.length) key.substring(prefix.length) else key
                        Log.i(TAG, "[KILAUD STREAM BRIDGE] Matching setting for $pluginName: '$cleanKey' (Original: '$key')")
                        if (value is String) {
                            try {
                                pluginSettings[cleanKey] = APIHolder.mapper.readValue(value, Any::class.java)
                            } catch (e: Exception) {
                                pluginSettings[cleanKey] = value
                            }
                        } else {
                            pluginSettings[cleanKey] = value
                        }
                    }
                }
                if (pluginSettings.isEmpty()) {
                    Log.w(TAG, "[KILAUD STREAM BRIDGE] No settings found for plugin: '$pluginName' with prefix: '$prefix'")
                } else {
                    Log.i(TAG, "[KILAUD STREAM BRIDGE] Returning ${pluginSettings.size} settings for plugin: '$pluginName'")
                }
                bridgeResult.success(pluginSettings)
            }

            "setExtensionSettings" -> {
                val pluginName = call.argument<String>("pluginName")
                val key = call.argument<String>("key")
                val value = call.argument<Any>("value")
                if (pluginName == null || key == null) {
                    bridgeResult.error("INVALID_ARGUMENT", "pluginName and key are required", null)
                    return
                }
                Log.i(TAG, "[CS_BRIDGE] setExtensionSettings for plugin: '$pluginName', key: '$key', value: $value")
                DataStore.setKey(pluginName, key, value)
                bridgeResult.success(true)
            }

            "getRegisteredProviders" -> bridgeResult.success(getRegisteredProviders())

            "loadPlugin" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    bridgeResult.error("INVALID_ARGUMENT", "Path is null", null)
                    return
                }
                val file = File(path)
                if (!file.exists()) {
                    bridgeResult.error("FILE_NOT_FOUND", "File not found: $path", null)
                    return
                }
                scope.launch {
                    try {
                        val useCtx = activity ?: context
                        val success = PluginManager.loadPlugin(useCtx, file)
                        if (!success) {
                            Log.e(TAG, "PluginManager.loadPlugin returned false for $path")
                        }
                        val registered = getRegisteredProviders()
                        Log.i(TAG, "Registered providers after load: ${registered.map { it["name"] }}")
                        withContext(Dispatchers.Main) { bridgeResult.success(success) }
                    } catch (e: Exception) {
                        Log.e(TAG, "loadPlugin failed for $path", e)
                        withContext(Dispatchers.Main) { bridgeResult.error("LOAD_FAILED", e.message, null) }
                    }
                }
            }

            "downloadPlugin" -> {
                val pluginUrl = call.argument<String>("pluginUrl")
                val internalName = call.argument<String>("internalName")
                val repositoryUrl = call.argument<String>("repositoryUrl")

                if (pluginUrl.isNullOrBlank() || internalName.isNullOrBlank()) {
                    bridgeResult.error(
                        "INVALID_ARGUMENT",
                        "pluginUrl and internalName are required",
                        null
                    )
                    return
                }

                scope.launch {
                    try {
                        val success = downloadPlugin(
                            pluginUrl = pluginUrl,
                            internalName = internalName,
                            repositoryUrl = repositoryUrl.orEmpty()
                        )
                        withContext(Dispatchers.Main) { bridgeResult.success(success) }
                    } catch (e: Exception) {
                        Log.e(TAG, "downloadPlugin failed for $pluginUrl", e)
                        withContext(Dispatchers.Main) {
                            bridgeResult.error("DOWNLOAD_FAILED", e.message, null)
                        }
                    }
                }
            }

            "deletePlugin" -> {
                val internalName = call.argument<String>("internalName")
                val repositoryUrl = call.argument<String>("repositoryUrl")
                if (internalName.isNullOrBlank()) {
                    bridgeResult.error("INVALID_ARGUMENT", "internalName is required", null)
                    return
                }
                scope.launch {
                    try {
                        val deleted = deletePlugin(
                            internalName = internalName,
                            repositoryUrl = repositoryUrl.orEmpty()
                        )
                        withContext(Dispatchers.Main) { bridgeResult.success(deleted) }
                    } catch (e: Exception) {
                        Log.e(TAG, "deletePlugin failed for $internalName", e)
                        withContext(Dispatchers.Main) {
                            bridgeResult.error("DELETE_FAILED", e.message, null)
                        }
                    }
                }
            }

            "search" -> {
                val query = call.argument<String>("query") ?: ""
                val page = call.argument<Int>("page") ?: 1
                val apiName = call.argument<String>("apiName")

                scope.launch {
                    try {
                        val res = if (apiName != null) {
                            Log.i(TAG, "[CS_BRIDGE] Searching for provider with apiName: '$apiName'")
                            val provider = findProvider(apiName)
                                ?: run {
                                    val available = APIHolder.apis.map { it.name }
                                    val msg = "[CS_BRIDGE] Provider '$apiName' not found. Available in APIHolder: $available"
                                    Log.e(TAG, msg)
                                    withContext(Dispatchers.Main) { bridgeResult.error("NOT_FOUND", msg, null) }
                                    return@launch
                                }
                            Log.i(TAG, "[CS_BRIDGE] Found provider: ${provider.name}, calling search...")
                            CloudStreamSourceMethods(provider).search(query, page)
                        } else {
                            val allItems = APIHolder.apis.flatMap { provider ->
                                CloudStreamSourceMethods(provider).search(query, page)["list"]
                                    as? List<Map<String, Any?>> ?: emptyList()
                            }
                            mapOf("list" to allItems, "hasNextPage" to false)
                        }
                        withContext(Dispatchers.Main) { bridgeResult.success(res) }
                    } catch (e: Exception) {
                        Log.e(TAG, "search failed", e)
                        withContext(Dispatchers.Main) { bridgeResult.error("SEARCH_FAILED", e.message, null) }
                    }
                }
            }

            "getDetail" -> {
                val apiName = call.argument<String>("apiName") ?: ""
                val url = call.argument<String>("url") ?: ""
                scope.launch {
                    try {
                        val provider = findProvider(apiName)
                            ?: run {
                                withContext(Dispatchers.Main) {
                                    bridgeResult.error("NOT_FOUND", "Provider '$apiName' not found", null)
                                }
                                return@launch
                            }
                        val res = CloudStreamSourceMethods(provider).getDetails(url)
                        withContext(Dispatchers.Main) { bridgeResult.success(res) }
                    } catch (e: Exception) {
                        Log.e(TAG, "getDetail failed", e)
                        withContext(Dispatchers.Main) { bridgeResult.error("DETAIL_FAILED", e.message, null) }
                    }
                }
            }

            "getVideoList" -> {
                val apiName = call.argument<String>("apiName") ?: ""
                val url = call.argument<String>("url") ?: ""
                scope.launch {
                    try {
                        val provider = findProvider(apiName)
                            ?: run {
                                withContext(Dispatchers.Main) {
                                    bridgeResult.error("NOT_FOUND", "Provider '$apiName' not found", null)
                                }
                                return@launch
                            }
                        val res = CloudStreamSourceMethods(provider).loadLinks(url)
                        withContext(Dispatchers.Main) { bridgeResult.success(res) }
                    } catch (e: Exception) {
                        Log.e(TAG, "getVideoList failed", e)
                        withContext(Dispatchers.Main) { bridgeResult.error("VIDEO_FAILED", e.message, null) }
                    }
                }
            }

            else -> bridgeResult.notImplemented()
        }
    }

    private fun findProvider(apiName: String) =
        APIHolder.apis.find { it.name == apiName }
            ?: APIHolder.apis.find { it.name.equals(apiName, ignoreCase = true) }

    fun initialize(context: Context) {
        DataStore.init(context)
        AcraApplication.context = context
        CloudStreamApp.context = context
    }

    private suspend fun downloadPlugin(
        pluginUrl: String,
        internalName: String,
        repositoryUrl: String
    ): Boolean = withContext(Dispatchers.IO) {
        val pluginRepositoryUrl = repositoryUrl.ifBlank { pluginUrl }
        val targetFile = PluginManager.getPluginPath(context, internalName, pluginRepositoryUrl)


        if (PluginManager.plugins.containsKey(targetFile.absolutePath)) {
            PluginManager.unloadPlugin(targetFile.absolutePath)
        }
        targetFile.parentFile?.mkdirs()
        if (targetFile.exists()) targetFile.setWritable(true)

        val downloaded = com.lagradost.cloudstream3.plugins.RepositoryManager
            .downloadPluginToFile(pluginUrl, targetFile)
        if (downloaded == null) {
            Log.e(TAG, "Download failed for $pluginUrl")
            return@withContext false
        }

        val useCtx = activity ?: context
        if (useCtx is android.app.Application) {
            Log.w(TAG, "Loading plugin '$internalName' with Application context. This may cause ClassCastException in some plugins.")
        }
        val success = PluginManager.loadPlugin(useCtx, downloaded)
        if (success) {
            Log.i(TAG, "Plugin $internalName downloaded and loaded from ${downloaded.absolutePath}")
        } else {
            Log.e(TAG, "Plugin $internalName downloaded but failed to load")
        }
        success
    }

    private suspend fun deletePlugin(
        internalName: String,
        repositoryUrl: String
    ): Boolean = withContext(Dispatchers.IO) {
        val pluginRepositoryUrl = repositoryUrl.ifBlank { internalName }
        val targetFile = PluginManager.getPluginPath(context, internalName, pluginRepositoryUrl)

        val pluginData = PluginManager.getPluginsOnline()
            .firstOrNull { it.internalName == internalName || it.filePath == targetFile.absolutePath }

        val fileToDelete = if (pluginData != null) File(pluginData.filePath) else targetFile

        Log.i(TAG, "Deleting plugin $internalName at ${fileToDelete.absolutePath}")

        if (PluginManager.plugins.containsKey(fileToDelete.absolutePath)) {
            PluginManager.unloadPlugin(fileToDelete.absolutePath)
        }


        val deleted = if (fileToDelete.exists()) {
            fileToDelete.setWritable(true)
            fileToDelete.delete()
        } else {
            Log.w(TAG, "Plugin file not found: ${fileToDelete.absolutePath}")
            true 
        }

        if (pluginData != null) {
            val remaining = PluginManager.getPluginsOnline()
                .filter { it.filePath != fileToDelete.absolutePath }
            com.lagradost.cloudstream3.CloudStreamApp.setKey(
                "PLUGINS_KEY", remaining
            )
        }

        fileToDelete.parentFile?.let { dir ->
            if (dir.exists() && dir.listFiles()?.isEmpty() == true) dir.delete()
        }

        deleted
    }

    suspend fun loadLocalPlugins(context: Context) = withContext(Dispatchers.IO) {
        val pluginDir = File("${context.filesDir}/${PluginManager.ONLINE_PLUGINS_FOLDER}")
        if (pluginDir.exists()) {
            pluginDir.listFiles()?.forEach { repoDir ->
                if (repoDir.isDirectory) {
                    repoDir.listFiles()?.forEach { pluginFile ->
                        if (pluginFile.extension == "cs3") {
                            val useCtx = activity ?: context
                            if (useCtx is android.app.Application) {
                                Log.w(TAG, "Loading local plugin '${pluginFile.name}' with Application context.")
                            }
                            PluginManager.loadPlugin(useCtx, pluginFile)
                        }
                    }
                } else if (repoDir.extension == "cs3") {
                    val useCtx = activity ?: context
                    if (useCtx is android.app.Application) {
                        Log.w(TAG, "Loading local plugin '${repoDir.name}' with Application context.")
                    }
                    PluginManager.loadPlugin(useCtx, repoDir)
                }
            }
        }
    }

    fun getRegisteredProviders(): List<Map<String, Any?>> {
        val pluginData = PluginManager.getPluginsOnline()
        val providers = APIHolder.apis.map { provider ->
            val data = pluginData.firstOrNull { it.filePath == provider.sourcePlugin }
            mapOf(
                "id" to provider.name,
                "name" to provider.name,
                "url" to provider.mainUrl,
                "language" to provider.lang,
                "plugin" to (provider.sourcePlugin ?: ""),
                "pluginUrl" to (data?.url ?: ""),
                "iconUrl" to (data?.iconUrl ?: ""),
                "internalName" to (data?.internalName ?: provider.name),
                "itemType" to 1  
            )
        }
        val names = providers.map { it["name"] }
        Log.i(TAG, "[CS_BRIDGE] getRegisteredProviders returning ${providers.size} providers: $names")
        return providers
    }
}
