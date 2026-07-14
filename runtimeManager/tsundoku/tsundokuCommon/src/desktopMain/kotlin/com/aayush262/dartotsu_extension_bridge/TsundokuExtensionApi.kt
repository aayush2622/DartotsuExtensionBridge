package com.aayush262.dartotsu_extension_bridge

import android.annotation.SuppressLint
import android.app.Application
import android.os.Looper
import androidx.preference.CheckBoxPreference
import androidx.preference.EditTextPreference
import androidx.preference.ListPreference
import androidx.preference.MultiSelectListPreference
import androidx.preference.SwitchPreferenceCompat
import com.aayush262.dartotsu_extension_bridge.aniyomi.*
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.google.gson.Gson
import eu.kanade.tachiyomi.PreferenceScreen
import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.serialization.json.Json
import org.koin.core.context.GlobalContext
import org.koin.core.context.startKoin
import org.koin.dsl.module
import org.koin.mp.KoinPlatformTools
import uy.kohesive.injekt.injectLazy
import xyz.nulldev.androidcompat.androidimpl.CustomContext
import xyz.nulldev.androidcompat.xyz.nulldev.androidcompat.androidCompatModule
import java.io.File
import kotlin.collections.set
import kotlin.getValue

actual object PlatformInit {
    actual fun initializeAndroid(context: Any) {}

    actual fun initializeDesktop(basePath: String) {
        val root = File(basePath).apply { mkdirs() }
        CommonDesktopApi.init(root.absolutePath)
        if (GlobalContext.getOrNull() != null) {
            Logger.log("Koin already started")
            return
        }
        val context = object : Application() {}
        val mainLoop = object : Thread() {
            override fun run() {
                Looper.prepareMainLooper()
                Looper.loop()
            }
        }
        mainLoop.start()
        startKoin {
            modules(
                listOf(
                    module {
                        single<Application> { context }
                        single { NetworkHelper(context) }
                        single { Json { ignoreUnknownKeys = true } }
                        single { TsundokuExtensionApi() }
                    },
                    androidCompatModule(root),
                )
            )
        }
        val app: CustomContext by KoinPlatformTools.defaultContext().get().inject()
        context.attach(app)
        context.onCreate()
    }

    private fun media(sourceId: String, isAnime: Boolean) = if (isAnime) AnimeSourceMethods(sourceId)
    else MangaSourceMethods(sourceId)

    private val gson = Gson()

    private fun encode(data: Any?): String =
        gson.toJson(data)

    @Suppress("UNCHECKED_CAST")
    private fun decode(json: String): Map<String, Any?> =
        gson.fromJson(json, Map::class.java) as Map<String, Any?>
    val preferenceScreenMap = mutableMapOf<String, PreferenceScreen>()
    private val context: Application by injectLazy()
    @SuppressLint("RestrictedApi")

    actual suspend fun getPreference(sourceId: String, isAnime: Boolean): String {
        val source = media(sourceId, isAnime)

        val prefs = source.getSourcePreferences()

        val screen = PreferenceScreen(context)
        screen.sharedPreferences = prefs

        source.setupPreferenceScreen(screen)

        preferenceScreenMap[sourceId] = screen

        val result = screen.preferences.mapIndexed { index, pref ->

            val key = pref.key

            val value = try {
                pref.currentValue
            } catch (_: Exception) {
                null
            }

            val type = when (pref) {
                is ListPreference -> "list"
                is MultiSelectListPreference -> "multi_select"
                is SwitchPreferenceCompat -> "switch"
                is EditTextPreference -> "text"
                is CheckBoxPreference -> "checkbox"
                else -> "other"
            }
            val summary = pref.summary?.toString()
            val formattedSummary = if (summary?.contains("%s") == true) {

                val entry = when (pref) {
                    is ListPreference -> {
                        val current = pref.currentValue?.toString()

                        val index = pref.entryValues
                            ?.map { it.toString() }
                            ?.indexOf(current)

                        if (index != null && index >= 0) {
                            pref.entries?.get(index)?.toString()
                        } else {
                            current
                        }
                    }

                    else -> pref.currentValue?.toString()
                }

                summary.replace("%s", entry ?: "")
            } else {
                summary
            }
            val map = mutableMapOf(
                "position" to index,
                "key" to key,
                "title" to pref.title?.toString(),
                "summary" to formattedSummary,
                "enabled" to pref.isEnabled,
                "type" to type,
                "value" to value
            )

            when (pref) {

                is ListPreference -> {
                    val entries = pref.entries?.map { it.toString() } ?: emptyList()
                    val values = pref.entryValues?.map { it.toString() } ?: emptyList()


                    map["entries"] = entries
                    map["entryValues"] = values
                }

                is MultiSelectListPreference -> {
                    val entries = pref.entries?.map { it.toString() } ?: emptyList()
                    val values = pref.entryValues?.map { it.toString() } ?: emptyList()

                    map["entries"] = entries
                    map["entryValues"] = values
                }
            }

            map
        }

        return encode(result)
    }
    actual suspend fun saveSourcePreference(sourceId: String, key: String, value: String?): Boolean {

        val screen = preferenceScreenMap[sourceId] ?: return false

        val pref = screen.preferences.find { it.key == key }
        if (pref == null) {
            return false
        }

        if (value == null) {
            return false
        }

        val payload = try {
            decode(value)
        } catch (_: Exception) {
            return false
        }

        val raw = payload["value"]

        val newValue: Any = when (pref.defaultValueType) {

            "String" -> raw as? String ?: ""
            "Boolean" -> raw as? Boolean ?: false
            "Set<String>" -> (raw as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet<String>()
            else -> {
                return false
            }
        }


        pref.saveNewValue(newValue)
        pref.callChangeListener(newValue)

        return true

    }
}