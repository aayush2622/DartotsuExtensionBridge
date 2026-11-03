package com.aayush262.dartotsu_extension_bridge.cloudStream

import android.content.SharedPreferences
import com.aayush262.dartotsu_extension_bridge.cloudStream.AndroidPreferenceRecorder.Type
import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.google.gson.Gson
import com.google.gson.JsonParser
import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.utils.PREFERENCES_NAME

/**
 * Same generic switch/text settings as desktop
 * ([SourcePreferences.desktop.kt][../../desktopMain/.../SourcePreferences.desktop.kt]):
 * no native settings screen is opened, the preferences the extension reads
 * and writes while actually running are recorded
 * ([AndroidPreferenceRecorder]) and offered as plain switches and text
 * fields. Keys look like `store::key`; CloudStream's own `setKey`/`getKey`
 * store (`PREFERENCES_NAME`) keeps JSON, decoded for display and encoded on
 * save.
 */
actual object SourcePreferences {
    private const val SEPARATOR = "::"
    private val gson = Gson()
    private val internalName = Regex("(time|date|expir|stamp|last|cache|count|version|cookie|session|^_)", RegexOption.IGNORE_CASE)

    actual fun get(provider: MainAPI): String {
        val owner = ownerOf(provider) ?: return "[]"
        val entries = AndroidPreferenceRecorder.keysFor(owner)
            .filter(::isUserSetting)
            .mapNotNull(::toJson)
        return gson.toJson(entries)
    }

    actual fun save(provider: MainAPI, key: String, value: String?): Boolean {
        val owner = ownerOf(provider) ?: return false
        val (storeName, prefKey) = key.split(SEPARATOR, limit = 2).takeIf { it.size == 2 } ?: return false
        val recorded = AndroidPreferenceRecorder.keysFor(owner).firstOrNull { it.store == storeName && it.key == prefKey }
            ?: return false
        val raw = value?.let { JsonParser.parseString(it).asJsonObject.get("value") }
        val prefs = store(storeName) ?: return false

        return try {
            prefs.edit().apply {
                when {
                    raw == null || raw.isJsonNull -> remove(prefKey)
                    storeName == PREFERENCES_NAME && raw.asString.isBlank() -> remove(prefKey)
                    storeName == PREFERENCES_NAME -> putString(prefKey, encodeDataStore(storeName, prefKey, raw.asString))
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

    private fun ownerOf(provider: MainAPI): String? =
        provider.javaClass.classLoader?.let(AndroidPreferenceRecorder::ownerFor)

    private fun isUserSetting(key: AndroidPreferenceRecorder.Key): Boolean {
        if (key.type == Type.LONG || key.type == Type.FLOAT) return false
        return !internalName.containsMatchIn(key.key)
    }

    private fun store(name: String): SharedPreferences? = AndroidPreferenceRecorder.storeNamed(name)

    private fun toJson(key: AndroidPreferenceRecorder.Key): Map<String, Any?>? {
        val prefs = store(key.store) ?: return null
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

    private fun encodeDataStore(storeName: String, key: String, text: String): String {
        val current = runCatching { store(storeName)?.getString(key, null) }.getOrNull()
        val element = current?.let { runCatching { JsonParser.parseString(it) }.getOrNull() }
        return when {
            element != null && element.isJsonPrimitive && element.asJsonPrimitive.isBoolean -> text.trim().toBoolean().toString()
            element != null && element.isJsonPrimitive && element.asJsonPrimitive.isNumber && text.trim().toDoubleOrNull() != null -> text.trim()
            element == null && text.trim().lowercase() in setOf("true", "false") -> text.trim().lowercase()
            element == null && text.trim().toDoubleOrNull() != null -> text.trim()
            else -> gson.toJson(text)
        }
    }

    private fun number(value: Any?): Number? = when (value) {
        is Number -> value
        is String -> value.toDoubleOrNull()
        else -> null
    }

    /** `showboxToken` / `show_box_token` -> `Show box token`. */
    private fun humanize(key: String): String {
        val words = key
            .replace(Regex("([a-z0-9])([A-Z])"), "$1 $2")
            .replace(Regex("[_\\-.]+"), " ")
            .trim()
            .lowercase()
        return words.replaceFirstChar { it.uppercase() }.ifEmpty { key }
    }
}
