package com.example.dartotsu_extension_bridge

import android.content.Context
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext


class AniyomiBridge(private val context: Context) : MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInstalledAnimeExtensions" -> getInstalledAnimeExtensions(result)
            "getInstalledMangaExtensions" -> getInstalledMangaExtensions(result)
            "fetchAnimeExtensions" -> fetchAnimeExtensions(call, result)
            "fetchMangaExtensions" -> fetchMangaExtensions(call, result)
            else -> result.notImplemented()
        }
    }

    private fun getInstalledAnimeExtensions(result: MethodChannel.Result) {
        val extensionManager = Injekt.get<AniyomiExtensionManager>()
        try {
            val installedExtensions = extensionManager.fetchInstalledAnimeExtensions()
                ?.map { ext ->
                    mapOf(
                        "name" to ext.name,
                        "pkgName" to ext.pkgName,
                        "versionName" to ext.versionName,
                        "libVersion" to ext.libVersion,
                        "supportedLanguages" to ext.sources.map { it.lang },
                        "lang" to ext.lang,
                        "isNsfw" to ext.isNsfw,
                        "icon" to ext.iconUrl,
                        "hasUpdate" to ext.hasUpdate,
                        "isObsolete" to ext.isObsolete,
                        "isUnofficial" to ext.isUnofficial,
                    )
                }
            result.success(installedExtensions)
        } catch (e: Exception) {
            e.printStackTrace()
            result.error("ERROR", "Failed to get installed extensions: ${e.message}", null)
        }
    }
    private fun getInstalledMangaExtensions(result: MethodChannel.Result) {
        val extensionManager = Injekt.get<AniyomiExtensionManager>()
        try {
            val installedExtensions = extensionManager.fetchInstalledMangaExtensions()
                ?.map { ext ->
                    mapOf(
                        "name" to ext.name,
                        "pkgName" to ext.pkgName,
                        "versionName" to ext.versionName,
                        "libVersion" to ext.libVersion,
                        "supportedLanguages" to ext.sources.map { it.lang },
                        "lang" to ext.lang,
                        "isNsfw" to ext.isNsfw,
                        "icon" to ext.iconUrl,
                        "hasUpdate" to ext.hasUpdate,
                        "isObsolete" to ext.isObsolete,
                        "isUnofficial" to ext.isUnofficial,
                    )
                }
            result.success(installedExtensions)
        } catch (e: Exception) {
            e.printStackTrace()
            result.error("ERROR", "Failed to get installed extensions: ${e.message}", null)
        }
    }

    private fun fetchAnimeExtensions(call: MethodCall, result: MethodChannel.Result) {
        val extensionManager = Injekt.get<AniyomiExtensionManager>()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val args = call.arguments as? List<*>
                val repos = args?.filterIsInstance<String>() ?: emptyList()
                val availableExtensions = extensionManager.findAvailableAnimeExtensions(repos)

                val mapped = availableExtensions.map { ext ->
                    mapOf(
                        "name" to ext.name,
                        "pkgName" to ext.pkgName,
                        "versionName" to ext.versionName,
                        "libVersion" to ext.libVersion,
                        "supportedLanguages" to ext.sources.map { it.lang },
                        "lang" to ext.lang,
                        "isNsfw" to ext.isNsfw,
                        "icon" to ext.iconUrl,
                    )
                }

                withContext(Dispatchers.Main) {
                    result.success(mapped)
                }
            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    result.error("ERROR", "Failed to fetch available extensions: ${e.message}", null)
                }
            }
        }
    }
    private fun fetchMangaExtensions(call: MethodCall, result: MethodChannel.Result) {
        val extensionManager = Injekt.get<AniyomiExtensionManager>()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val args = call.arguments as? List<*>
                val repos = args?.filterIsInstance<String>() ?: emptyList()
                val availableExtensions = extensionManager.findAvailableMangaExtensions(repos)

                val mapped = availableExtensions.map { ext ->
                    mapOf(
                        "name" to ext.name,
                        "pkgName" to ext.pkgName,
                        "versionName" to ext.versionName,
                        "libVersion" to ext.libVersion,
                        "supportedLanguages" to ext.sources.map { it.lang },
                        "lang" to ext.lang,
                        "isNsfw" to ext.isNsfw,
                        "icon" to ext.iconUrl,
                    )
                }

                withContext(Dispatchers.Main) {
                    result.success(mapped)
                }
            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    result.error("ERROR", "Failed to fetch available extensions: ${e.message}", null)
                }
            }
        }
    }
}