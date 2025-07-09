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
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingletonFactory

/** DartotsuExtensionBridgePlugin */
class DartotsuExtensionBridgePlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var context: Context
  private lateinit var resultHolder: MethodChannel.Result

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val channel = MethodChannel(binding.binaryMessenger, "test")
    channel.setMethodCallHandler(this)
    context = binding.applicationContext
    Injekt.addSingletonFactory<Application> { context as Application }
    Injekt.addSingletonFactory { NetworkHelper(context) }
    Injekt.addSingletonFactory { NetworkHelper(context).client }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    if (call.method == "getAnimeTitles") {
      resultHolder = result // hold result for async use
      loadAndReturnTitles()
    } else {
      result.notImplemented()
    }
  }

  @OptIn(DelicateCoroutinesApi::class)
  private fun loadAndReturnTitles() {
    GlobalScope.launch {
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
        print(titles.toString())
        // Return result to Dart
        withContext(Dispatchers.Main) {
          resultHolder.success(titles)
        }
      } catch (e: Exception) {
        e.printStackTrace()
        withContext(Dispatchers.Main) {
          resultHolder.error("EXTENSION_ERROR", e.message, null)
        }
      }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}

