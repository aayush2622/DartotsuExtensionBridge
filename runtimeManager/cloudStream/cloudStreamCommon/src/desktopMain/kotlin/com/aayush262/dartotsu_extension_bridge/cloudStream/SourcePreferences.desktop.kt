package com.aayush262.dartotsu_extension_bridge.cloudStream

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import androidx.fragment.app.Fragment
import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.aayush262.dartotsu_extension_bridge.prefs.PreferenceRecorder
import com.aayush262.dartotsu_extension_bridge.prefs.PreferenceRecorder.Type
import com.google.gson.Gson
import com.google.gson.JsonParser
import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.plugins.Plugin
import com.lagradost.cloudstream3.utils.PREFERENCES_NAME
import org.koin.mp.KoinPlatformTools
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/**
 * Desktop has no Android views, so an extension's settings screen can't be
 * shown. Instead the preferences it uses are recorded as it runs
 * ([PreferenceRecorder]) and offered as plain switches and text fields: a
 * boolean becomes a switch, anything else an editable value. To find keys
 * early, the extension's settings screen is started once off-screen; what it
 * reads before failing on the missing views is recorded too, and listed first.
 *
 * Keys look like `store::key`. CloudStream's own `setKey`/`getKey` store
 * keeps JSON, which is decoded for display and encoded on save.
 */
actual object SourcePreferences {
    private const val SEPARATOR = "::"
    private val gson = Gson()
    private val probed = ConcurrentHashMap.newKeySet<String>()
    private val internalName = Regex("(time|date|expir|stamp|last|cache|count|version|cookie|session|^_)", RegexOption.IGNORE_CASE)

    private val context: Context by lazy {
        val app: Application by KoinPlatformTools.defaultContext().get().inject()
        app.applicationContext
    }

    actual fun get(provider: MainAPI): String {
        probeSettingsScreen(provider)
        val loader = provider.javaClass.classLoader ?: return "[]"
        val entries = PreferenceRecorder.keysFor(loader)
            .filter(::isUserSetting)
            .mapNotNull(::toJson)
        return gson.toJson(entries)
    }

    actual fun save(provider: MainAPI, key: String, value: String?): Boolean {
        val loader = provider.javaClass.classLoader ?: return false
        val (storeName, prefKey) = key.split(SEPARATOR, limit = 2).takeIf { it.size == 2 } ?: return false
        val recorded = PreferenceRecorder.keysFor(loader).firstOrNull { it.store == storeName && it.key == prefKey }
            ?: return false
        val raw = value?.let { JsonParser.parseString(it).asJsonObject.get("value") }
        val prefs = store(storeName)

        return try {
            prefs.edit().apply {
                when {
                    raw == null || raw.isJsonNull -> remove(prefKey)
                    storeName == PREFERENCES_NAME -> putString(prefKey, encodeDataStore(recorded, raw.asString))
                    else -> when (recorded.type) {
                        Type.BOOLEAN -> putBoolean(prefKey, raw.asBoolean)
                        Type.INT -> putInt(prefKey, raw.asString.trim().toInt())
                        Type.LONG -> putLong(prefKey, raw.asString.trim().toLong())
                        Type.FLOAT -> putFloat(prefKey, raw.asString.trim().toFloat())
                        Type.STRING_SET -> putStringSet(
                            prefKey,
                            raw.asString.split(',').map { it.trim() }.filter { it.isNotEmpty() }.toMutableSet(),
                        )
                        Type.STRING -> putString(prefKey, raw.asString)
                    }
                }
            }.commit()
        } catch (e: Throwable) {
            Logger.log("Could not save $key for ${provider.name}: ${e.message}", LogLevel.WARNING)
            false
        }
    }

    /**
     * Starts the extension's settings screen once, off-screen, so the
     * preferences it reads while being built are recorded. It stops at the
     * first missing Android view; only the reads before that count.
     */
    private fun probeSettingsScreen(provider: MainAPI) {
        val loader = provider.javaClass.classLoader ?: return
        val plugin = ExtensionLoader.plugins.values
            .map { it.plugin }
            .firstOrNull { it.javaClass.classLoader === loader } as? Plugin ?: return
        val open = plugin.openSettings ?: return
        if (!probed.add(plugin.filename ?: plugin.javaClass.name)) return

        if (Fragment.hostContext == null) Fragment.hostContext = context
        val thread = Thread {
            try {
                PreferenceRecorder.whileBuildingSettings { open(context) }
            } catch (_: Throwable) {
                // Expected: the screen needs views desktop doesn't have.
            }
        }
        thread.isDaemon = true
        thread.start()
        thread.join(TimeUnit.SECONDS.toMillis(5))
    }

    private fun isUserSetting(key: PreferenceRecorder.Key): Boolean {
        if (key.fromSettingsScreen) return true
        if (key.type == Type.LONG || key.type == Type.FLOAT) return false
        return !internalName.containsMatchIn(key.key)
    }

    private fun store(name: String): SharedPreferences =
        PreferenceRecorder.storeNamed(name) ?: context.getSharedPreferences(name, Context.MODE_PRIVATE)

    private fun toJson(key: PreferenceRecorder.Key): Map<String, Any?>? {
        val prefs = store(key.store)
        val id = key.store + SEPARATOR + key.key
        val title = humanize(key.key)

        if (key.store == PREFERENCES_NAME) {
            val stored = runCatching { prefs.getString(key.key, null) }.getOrNull()
            val element = stored?.let { runCatching { JsonParser.parseString(it) }.getOrNull() }
            return if (element != null && element.isJsonPrimitive && element.asJsonPrimitive.isBoolean) {
                mapOf("key" to id, "type" to "switch", "title" to title, "value" to element.asBoolean)
            } else {
                val text = when {
                    element == null || element.isJsonNull -> ""
                    element.isJsonPrimitive -> element.asString
                    else -> return null
                }
                mapOf("key" to id, "type" to "text", "title" to title, "value" to text)
            }
        }

        return runCatching {
            when (key.type) {
                Type.BOOLEAN -> mapOf(
                    "key" to id, "type" to "switch", "title" to title,
                    "value" to prefs.getBoolean(key.key, key.default as? Boolean ?: false),
                )
                Type.STRING_SET -> mapOf(
                    "key" to id, "type" to "text", "title" to title,
                    "summary" to "Comma separated",
                    "value" to prefs.getStringSet(key.key, emptySet()).orEmpty().joinToString(", "),
                )
                Type.INT -> mapOf("key" to id, "type" to "text", "title" to title, "value" to prefs.getInt(key.key, number(key.default)?.toInt() ?: 0).toString())
                Type.LONG -> mapOf("key" to id, "type" to "text", "title" to title, "value" to prefs.getLong(key.key, number(key.default)?.toLong() ?: 0L).toString())
                Type.FLOAT -> mapOf("key" to id, "type" to "text", "title" to title, "value" to prefs.getFloat(key.key, number(key.default)?.toFloat() ?: 0f).toString())
                Type.STRING -> mapOf(
                    "key" to id, "type" to "text", "title" to title,
                    "value" to prefs.getString(key.key, key.default as? String).orEmpty(),
                )
            }
        }.getOrNull()
    }

    private fun encodeDataStore(key: PreferenceRecorder.Key, text: String): String {
        val current = runCatching { store(key.store).getString(key.key, null) }.getOrNull()
        val element = current?.let { runCatching { JsonParser.parseString(it) }.getOrNull() }
        return when {
            element != null && element.isJsonPrimitive && element.asJsonPrimitive.isBoolean -> text.trim().toBoolean().toString()
            element != null && element.isJsonPrimitive && element.asJsonPrimitive.isNumber && text.trim().toDoubleOrNull() != null -> text.trim()
            else -> gson.toJson(text)
        }
    }

    private fun number(value: Any?): Number? = when (value) {
        is Number -> value
        is String -> value.toDoubleOrNull()
        else -> null
    }

    /** `showboxToken` / `show_box_token` → `Show box token`. */
    private fun humanize(key: String): String {
        val words = key
            .replace(Regex("([a-z0-9])([A-Z])"), "$1 $2")
            .replace(Regex("[_\\-.]+"), " ")
            .trim()
            .lowercase()
        return words.replaceFirstChar { it.uppercase() }.ifEmpty { key }
    }
}
