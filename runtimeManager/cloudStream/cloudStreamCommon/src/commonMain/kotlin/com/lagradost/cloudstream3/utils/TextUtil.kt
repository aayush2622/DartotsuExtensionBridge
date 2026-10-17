package com.lagradost.cloudstream3.utils

import android.content.Context

sealed class UiText {
    data class DynamicString(val value: String) : UiText() {
        override fun toString(): String = value
    }

    data class StringResource(val resId: Int, val args: List<Any>) : UiText()

    fun asStringNull(context: Context?): String? =
        try {
            asString(context ?: return null)
        } catch (e: Exception) {
            null
        }

    fun asString(context: Context): String = when (this) {
        is DynamicString -> value
        is StringResource -> {
            val str = context.getString(resId)
            if (args.isEmpty()) str
            else str.format(*args.map { if (it is UiText) it.asString(context) else it }.toTypedArray())
        }
    }
}

fun txt(value: String): UiText = UiText.DynamicString(value)

@JvmName("txtNull")
fun txt(value: String?): UiText? = UiText.DynamicString(value ?: return null)

fun txt(resId: Int, vararg args: Any): UiText = UiText.StringResource(resId, args.toList())

@JvmName("txtNull")
fun txt(resId: Int?, vararg args: Any?): UiText? {
    if (resId == null || args.any { it == null }) return null
    return UiText.StringResource(resId, args.filterNotNull())
}
