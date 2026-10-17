package com.aayush262.dartotsu_extension_bridge.prefs

import android.content.SharedPreferences
import com.aayush262.dartotsu_extension_bridge.CommonDesktopApi
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File
import java.net.URLClassLoader
import java.util.concurrent.ConcurrentHashMap

/**
 * Records which preferences each extension reads and writes, so its settings
 * can be shown and edited in the app without running its Android settings
 * screen.
 *
 * Every `SharedPreferences` read or write is attributed to the extension
 * whose code made it: the first class on the call stack loaded by an
 * extension's class loader (any loader below the one that loaded this
 * class). Keys, types and defaults are kept per extension jar and saved to
 * disk, so a key seen once shows up from the next start on.
 */
object PreferenceRecorder {

    enum class Type { BOOLEAN, STRING, INT, LONG, FLOAT, STRING_SET }

    data class Key(
        val store: String,
        val key: String,
        val type: Type,
        val default: Any? = null,
        /** Read while the extension's own settings screen was being built. */
        val fromSettingsScreen: Boolean = false,
    )

    private val ownLoaders: Set<ClassLoader> = generateSequence(PreferenceRecorder::class.java.classLoader) { it.parent }
        .toSet()

    private val walker = StackWalker.getInstance(StackWalker.Option.RETAIN_CLASS_REFERENCE)
    private val keys = ConcurrentHashMap<String, ConcurrentHashMap<String, Key>>()
    private val loaded = ConcurrentHashMap.newKeySet<String>()
    private val stores = ConcurrentHashMap<String, SharedPreferences>()
    private val settingsScreen = ThreadLocal<Boolean>()
    private val gson = Gson()

    /** Registers [prefs] as the store named [name], for writes made later. */
    fun store(name: String, prefs: SharedPreferences) {
        stores.putIfAbsent(name, prefs)
    }

    fun storeNamed(name: String): SharedPreferences? = stores[name]

    fun read(store: String, key: String, type: Type, default: Any?) = record(store, key, type, default)

    fun write(store: String, key: String, value: Any) {
        val type = when (value) {
            is Boolean -> Type.BOOLEAN
            is Int -> Type.INT
            is Long -> Type.LONG
            is Float, is Double -> Type.FLOAT
            is Set<*> -> Type.STRING_SET
            else -> Type.STRING
        }
        record(store, key, type, null)
    }

    /** Whether the current thread is building an extension's settings screen. */
    @JvmStatic
    fun isBuildingSettings(): Boolean = settingsScreen.get() == true

    /** Runs [block] with reads marked as coming from the settings screen. */
    fun <T> whileBuildingSettings(block: () -> T): T {
        settingsScreen.set(true)
        try {
            return block()
        } finally {
            settingsScreen.remove()
        }
    }

    /** Preferences recorded for code loaded by [loader]. */
    fun keysFor(loader: ClassLoader): List<Key> {
        val owner = ownerId(loader)
        ensureLoaded(owner)
        return keys[owner]?.values?.sortedWith(compareBy({ !it.fromSettingsScreen }, { it.store }, { it.key })).orEmpty()
    }

    private fun record(store: String, key: String, type: Type, default: Any?) {
        val loader = callerLoader() ?: return
        val owner = ownerId(loader)
        ensureLoaded(owner)
        val map = keys.getOrPut(owner) { ConcurrentHashMap() }
        val id = "$store\u0000$key"
        val fromScreen = settingsScreen.get() == true
        val existing = map[id]
        val next = Key(
            store = store,
            key = key,
            type = type,
            default = default ?: existing?.default,
            fromSettingsScreen = fromScreen || existing?.fromSettingsScreen == true,
        )
        if (existing != next) {
            map[id] = next
            save(owner, map.values)
        }
    }

    private fun callerLoader(): ClassLoader? = walker.walk { frames ->
        frames.map { it.declaringClass.classLoader }
            .filter { it != null && it !in ownLoaders }
            .findFirst()
            .orElse(null)
    }

    private fun ownerId(loader: ClassLoader): String {
        val jar = (loader as? URLClassLoader)?.urLs?.firstOrNull()?.path
        return File(jar ?: loader.toString()).nameWithoutExtension
    }

    private fun file(owner: String): File? = runCatching {
        File(CommonDesktopApi.rootDir, "extensions/settings/_keys/$owner.json")
    }.getOrNull()

    private fun ensureLoaded(owner: String) {
        if (!loaded.add(owner)) return
        val file = file(owner)?.takeIf { it.exists() } ?: return
        runCatching {
            val saved: List<Key> = gson.fromJson(file.readText(), object : TypeToken<List<Key>>() {}.type)
            val map = keys.getOrPut(owner) { ConcurrentHashMap() }
            saved.forEach { map.putIfAbsent("${it.store}\u0000${it.key}", it) }
        }
    }

    private fun save(owner: String, values: Collection<Key>) {
        val file = file(owner) ?: return
        runCatching {
            file.parentFile.mkdirs()
            file.writeText(gson.toJson(values.toList()))
        }
    }
}
