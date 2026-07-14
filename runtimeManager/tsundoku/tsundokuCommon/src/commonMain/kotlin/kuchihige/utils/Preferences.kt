package kuchihige.utils

import android.content.Context
import androidx.preference.Preference
import androidx.preference.PreferenceScreen

//  === Preference Helpers ====================================================

fun newPreference(context: Context, block: Preference.() -> Unit): Preference = Preference::class.java
    .getConstructor(Context::class.java)
    .newInstance(context)
    .apply(block)

fun PreferenceScreen.getPreference(index: Int): Preference? = try {
    PreferenceScreen::class.java
        .getMethod("getPreference", Int::class.javaPrimitiveType)
        .invoke(this, index) as? Preference
} catch (_: Exception) {
    null
}

fun PreferenceScreen.getPreferenceCount(): Int = try {
    PreferenceScreen::class.java
        .getMethod("getPreferenceCount")
        .invoke(this) as Int
} catch (_: Exception) {
    0
}

fun PreferenceScreen.removePreference(pref: Preference) {
    try {
        PreferenceScreen::class.java
            .getMethod("removePreference", Preference::class.java)
            .invoke(this, pref)
    } catch (_: Exception) {
    }
}

fun PreferenceScreen.removeAll() {
    try {
        PreferenceScreen::class.java
            .getMethod("removeAll")
            .invoke(this)
    } catch (_: Exception) {}
}

fun Preference.setIcon(resId: Int): Preference {
    try {
        // get the context from Preference via reflection
        val contextField = this.javaClass.getDeclaredField("mContext")
        contextField.isAccessible = true
        val context = contextField.get(this)

        val drawable = context.javaClass
            .getMethod("getDrawable", Int::class.javaPrimitiveType)
            .invoke(context, resId)

        val drawableClass = Class.forName("android.graphics.drawable.Drawable")

        this.javaClass
            .getMethod("setIcon", drawableClass)
            .invoke(this, drawable)

        // always reserve space for icon
        this.javaClass
            .getMethod("setIconSpaceReserved", Boolean::class.javaPrimitiveType)
            .invoke(this, true)
    } catch (e: Exception) {
        e.printStackTrace()
    }
    return this
}
