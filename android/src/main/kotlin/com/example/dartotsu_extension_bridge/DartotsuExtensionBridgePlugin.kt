package com.example.dartotsu_extension_bridge

import android.app.Application
import android.content.Context
import eu.kanade.tachiyomi.animesource.model.AnimeFilterList
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource
import eu.kanade.tachiyomi.extension.anime.model.AnimeLoadResult
import eu.kanade.tachiyomi.extension.util.ExtensionLoader
import eu.kanade.tachiyomi.network.NetworkHelper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingletonFactory
import uy.kohesive.injekt.api.get

/** DartotsuExtensionBridgePlugin */
class DartotsuExtensionBridgePlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var context: Context

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val channel = MethodChannel(binding.binaryMessenger, "test")
    channel.setMethodCallHandler(this)
    context = binding.applicationContext

    Injekt.addSingletonFactory<Application> { context as Application }
    Injekt.addSingletonFactory { NetworkHelper(context) }
    Injekt.addSingletonFactory { NetworkHelper(context).client }
    Injekt.addSingletonFactory { ExtensionManager(context) }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "getAnimeTitles" -> loadAndReturnTitles(result)
      "getInstalledExtensions" -> {
        val extensionManager = Injekt.get<ExtensionManager>()
        val installedExtensions = extensionManager.getInstalledExtensions()
        result.success(installedExtensions)
      }
      else -> result.notImplemented()
    }
  }


  private fun loadAndReturnTitles(result: MethodChannel.Result) {
    CoroutineScope(Dispatchers.Default).launch  {
      try {
        val extensions = ExtensionLoader.loadAnimeExtensions(context)
        val source = extensions
          .filterIsInstance<AnimeLoadResult.Success>()
          .map { it.extension }
          .first()
          .sources
          .first() as AnimeHttpSource

        val searchResult = source.getSearchAnime(1, "op", AnimeFilterList())
        val titles = searchResult.animes.map { it.title }

        withContext(Dispatchers.Main) {
          result.success(titles)
        }
      } catch (e: Exception) {
        e.printStackTrace()
        withContext(Dispatchers.Main) {
          result.error("EXTENSION_ERROR", e.message, null)
        }
      }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}

