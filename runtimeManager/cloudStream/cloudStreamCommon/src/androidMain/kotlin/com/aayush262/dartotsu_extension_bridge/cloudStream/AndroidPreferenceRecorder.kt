package com.aayush262.dartotsu_extension_bridge.cloudStream

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * Android's counterpart to desktop's `PreferenceRecorder`: records which
 * preferences an extension reads and writes, so its settings can be shown
 * and edited in the app the same generic way on both platforms, without
 * ever running the extension's own Android settings screen.
 *
 * Real Android has no `StackWalker` (desktop's attribution mechanism), so a
 * read/write is attributed to an extension by walking
 * `Thread.currentThread().stackTrace` and matching each frame's class
 * against the extensions' registered class loaders (first match wins,
 * cached per class name since a class always belongs to the same loader).
 */
object AndroidPreferenceRecorder {

    enum class Type { BOOLEAN, STRING, INT, LONG, FLOAT, STRING_SET }

    data class Key(
        val store: String,
        val key: String,
        val type: Type,
        val default: Any? = null,
    )

    private var rootDir: File? = null
    private val gson = Gson()

    private val extensionLoaders = ConcurrentHashMap<String, ClassLoader>()
    private val loaderOwners = ConcurrentHashMap<ClassLoader, String>()
    private val classOwner = ConcurrentHashMap<String, String>()

    private val keys = ConcurrentHashMap<String, ConcurrentHashMap<String, Key>>()
    private val lastKey = ConcurrentHashMap<String, Key>()
    private val loadedOwners = ConcurrentHashMap.newKeySet<String>()
    private val stores = ConcurrentHashMap<String, SharedPreferences>()

    fun init(context: Context) {
        rootDir = File(context.filesDir, "cloudstream-settings/_keys")
    }

    /** Lets calls made from [loader]'s classes be attributed to [owner]. */
    fun register(owner: String, loader: ClassLoader) {
        extensionLoaders[owner] = loader
        loaderOwners[loader] = owner
    }

    fun unregister(owner: String) {
        val loader = extensionLoaders.remove(owner)
        if (loader != null) loaderOwners.remove(loader)
        keys.remove(owner)
        lastKey.remove(owner)
        classOwner.entries.removeAll { it.value == owner }
    }

    fun ownerFor(loader: ClassLoader): String? = loaderOwners[loader]

    /** The preference [owner]'s code touched most recently. */
    fun lastTouched(owner: String): Key? = lastKey[owner]

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

    /** Preferences recorded for [owner]'s code. */
    fun keysFor(owner: String): List<Key> {
        ensureLoaded(owner)
        return keys[owner]?.values?.sortedWith(compareBy({ it.store }, { it.key })).orEmpty()
    }

    private fun record(store: String, key: String, type: Type, default: Any?) {
        val owner = callerOwner() ?: return
        ensureLoaded(owner)
        val map = keys.getOrPut(owner) { ConcurrentHashMap() }
        val id = "$store\u0000$key"
        val existing = map[id]
        val next = Key(store, key, type, default ?: existing?.default)
        lastKey[owner] = next
        if (existing != next) {
            map[id] = next
            save(owner, map.values)
        }
    }

    private fun callerOwner(): String? {
        for (frame in Thread.currentThread().stackTrace) {
            ownerOf(frame.className)?.let { return it }
        }
        return null
    }

    private fun ownerOf(className: String): String? {
        classOwner[className]?.let { return it }
        val owner = extensionLoaders.entries.firstOrNull { (_, loader) ->
            runCatching { Class.forName(className, false, loader).classLoader === loader }
                .getOrDefault(false)
        }?.key
        if (owner != null) classOwner[className] = owner
        return owner
    }

    private fun file(owner: String): File? = runCatching {
        File(rootDir, "$owner.json")
    }.getOrNull()

    private fun ensureLoaded(owner: String) {
        if (!loadedOwners.add(owner)) return
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
            file.parentFile?.mkdirs()
            file.writeText(gson.toJson(values.toList()))
        }
    }
}
