package com.aayush262.dartotsu_extension_bridge

import android.annotation.SuppressLint
import android.app.Application
import android.content.Context
import androidx.preference.*
import com.google.gson.Gson
import com.aayush262.dartotsu_extension_bridge.aniyomi.*
import eu.kanade.tachiyomi.PreferenceScreen
import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingletonFactory
import uy.kohesive.injekt.api.get
import androidx.core.content.edit

actual object PlatformInit {
    actual fun initializeAndroid(context: Any) {
        val ctx = context as? Context ?: return
        Injekt.addSingletonFactory<Application> { ctx as Application }
        Injekt.addSingletonFactory<Context> { ctx }
        Injekt.addSingletonFactory { NetworkHelper(ctx) }
        Injekt.addSingletonFactory { Injekt.get<NetworkHelper>().client }

        Injekt.addSingletonFactory {
            Json {
                ignoreUnknownKeys = true
                explicitNulls = false

            }
        }

        Injekt.addSingletonFactory { AniyomiExtensionManager() }

    }

    actual fun initializeDesktop(basePath: String) {}

    private fun media(sourceId: String, isAnime: Boolean) = if (isAnime) AnimeSourceMethods(sourceId)
    else MangaSourceMethods(sourceId)

    private val gson = Gson()

    private fun encode(data: Any?): String =
        gson.toJson(data)

    @Suppress("UNCHECKED_CAST")
    private fun decode(json: String): Map<String, Any?> =
        gson.fromJson(json, Map::class.java) as Map<String, Any?>
    private val sourcePreferences = mutableMapOf<String, MutableMap<String, Preference>>()
    @SuppressLint("RestrictedApi")

    actual suspend fun getPreference(sourceId: String, isAnime: Boolean): String {
        sourcePreferences.remove(sourceId)

        val context: Application = Injekt.get()

        val prefManager = PreferenceManager(context)

        prefManager.sharedPreferencesName = "source_$sourceId"
        prefManager.sharedPreferencesMode = Context.MODE_PRIVATE

        val screen = prefManager.createPreferenceScreen(context)

        media(sourceId, isAnime).setupPreferenceScreen(screen)

        return encode(screen.toDynamicMap(sourceId))
    }
    actual suspend fun saveSourcePreference(sourceId: String, key: String, value: String?): Boolean {
        val pref = sourcePreferences[sourceId]?.get(key) ?: return false

        if (value == null) {
            return false
        }

        val payload = try {
            decode(value)
        } catch (_: Exception) {
            return false
        }

        val raw = payload["value"]
        withContext(Dispatchers.Main) {

            val prefs = pref.sharedPreferences ?: return@withContext

            val convertedValue = when (raw) {
                is List<*> -> raw.filterIsInstance<String>().toMutableSet()
                is Set<*> -> raw.filterIsInstance<String>().toMutableSet()
                else -> raw
            }

            prefs.edit(commit = true) {

                when (convertedValue) {

                    is Boolean -> putBoolean(key, convertedValue)

                    is String -> putString(key, convertedValue)

                    is Int -> putInt(key, convertedValue)

                    is Long -> putLong(key, convertedValue)

                    is Float -> putFloat(key, convertedValue)

                    is Set<*> -> putStringSet(
                        key, convertedValue.filterIsInstance<String>().toMutableSet()
                    )

                    null -> remove(key)

                    else -> error("Unsupported preference type: ${convertedValue::class}")
                }
            }

            pref.onPreferenceChangeListener?.onPreferenceChange(pref, convertedValue)
        }

        return true
    }


    fun PreferenceScreen.toDynamicMap(sourceID: String): List<Map<String, Any?>> {
        val list = mutableListOf<Map<String, Any?>>()
        val clickMap = sourcePreferences.getOrPut(sourceID) { mutableMapOf() }
        fun traverse(prefGroup: PreferenceGroup) {
            for (i in 0 until prefGroup.preferenceCount) {
                val pref = prefGroup.getPreference(i)

                clickMap[pref.key] = pref
                val prefMap = mutableMapOf<String, Any?>(
                    "key" to pref.key,
                    "title" to pref.title.toString(),
                    "summary" to pref.summary?.toString(),
                    "enabled" to pref.isEnabled,
                    "type" to when (pref) {
                        is ListPreference -> "list"
                        is MultiSelectListPreference -> "multi_select"
                        is SwitchPreferenceCompat -> "switch"
                        is EditTextPreference -> "text"
                        is CheckBoxPreference -> "checkbox"
                        else -> "other"
                    }
                )
                when (pref) {
                    is ListPreference -> {
                        prefMap["entries"] = pref.entries.map { it.toString() }
                        prefMap["entryValues"] = pref.entryValues.map { it.toString() }
                        prefMap["value"] = pref.value
                    }

                    is MultiSelectListPreference -> {
                        prefMap["entries"] = pref.entries.map { it.toString() }
                        prefMap["entryValues"] = pref.entryValues.map { it.toString() }
                        prefMap["value"] = pref.values.toList()
                    }

                    is SwitchPreferenceCompat -> {
                        prefMap["value"] = pref.isChecked
                    }

                    is EditTextPreference -> {
                        prefMap["value"] = pref.text
                    }

                    is CheckBoxPreference -> {
                        prefMap["value"] = pref.isChecked
                    }

                    else -> {
                        prefMap["value"] = pref.sharedPreferences?.all?.get(pref.key)
                    }
                }
                list.add(prefMap)

                if (pref is PreferenceCategory) {
                    traverse(pref)
                }
            }
        }

        traverse(this)
        return list
    }


}
