package com.aayush262.dartotsu_extension_bridge.cloudStream

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import com.aayush262.dartotsu_extension_bridge.cloudStream.AndroidPreferenceRecorder.Type

/**
 * Wraps a real [SharedPreferences] so every read/write is also reported to
 * [AndroidPreferenceRecorder], attributed to whichever extension's code made
 * the call.
 */
private class RecordingSharedPreferences(
    private val name: String,
    private val real: SharedPreferences,
) : SharedPreferences by real {

    override fun getString(key: String, defValue: String?): String? {
        AndroidPreferenceRecorder.read(name, key, Type.STRING, defValue)
        return real.getString(key, defValue)
    }

    override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? {
        AndroidPreferenceRecorder.read(name, key, Type.STRING_SET, defValues)
        return real.getStringSet(key, defValues)
    }

    override fun getInt(key: String, defValue: Int): Int {
        AndroidPreferenceRecorder.read(name, key, Type.INT, defValue)
        return real.getInt(key, defValue)
    }

    override fun getLong(key: String, defValue: Long): Long {
        AndroidPreferenceRecorder.read(name, key, Type.LONG, defValue)
        return real.getLong(key, defValue)
    }

    override fun getFloat(key: String, defValue: Float): Float {
        AndroidPreferenceRecorder.read(name, key, Type.FLOAT, defValue)
        return real.getFloat(key, defValue)
    }

    override fun getBoolean(key: String, defValue: Boolean): Boolean {
        AndroidPreferenceRecorder.read(name, key, Type.BOOLEAN, defValue)
        return real.getBoolean(key, defValue)
    }

    override fun edit(): SharedPreferences.Editor = RecordingEditor(name, real.edit())
}

private class RecordingEditor(
    private val name: String,
    private val real: SharedPreferences.Editor,
) : SharedPreferences.Editor by real {

    override fun putString(key: String, value: String?): SharedPreferences.Editor {
        if (value != null) AndroidPreferenceRecorder.write(name, key, value)
        real.putString(key, value)
        return this
    }

    override fun putStringSet(key: String, values: MutableSet<String>?): SharedPreferences.Editor {
        if (values != null) AndroidPreferenceRecorder.write(name, key, values)
        real.putStringSet(key, values)
        return this
    }

    override fun putInt(key: String, value: Int): SharedPreferences.Editor {
        AndroidPreferenceRecorder.write(name, key, value)
        real.putInt(key, value)
        return this
    }

    override fun putLong(key: String, value: Long): SharedPreferences.Editor {
        AndroidPreferenceRecorder.write(name, key, value)
        real.putLong(key, value)
        return this
    }

    override fun putFloat(key: String, value: Float): SharedPreferences.Editor {
        AndroidPreferenceRecorder.write(name, key, value)
        real.putFloat(key, value)
        return this
    }

    override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor {
        AndroidPreferenceRecorder.write(name, key, value)
        real.putBoolean(key, value)
        return this
    }
}

/**
 * Wraps the host app's `Context` so every `getSharedPreferences` an
 * extension makes - directly, through `context.applicationContext`, or
 * through CloudStream's `DataStore` singleton - returns a recording
 * preferences object instead of the real one.
 */
class RecordingContext(base: Context) : ContextWrapper(base) {

    override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
        val real = super.getSharedPreferences(name, mode)
        val recording = RecordingSharedPreferences(name, real)
        AndroidPreferenceRecorder.store(name, recording)
        return recording
    }

    override fun getApplicationContext(): Context = this
}
