package com.aayush262.dartotsu_extension_bridge.ui

import android.view.View
import android.view.ViewGroup
import android.widget.CompoundButton
import android.widget.EditText
import android.widget.TextView

/**
 * Reads an inflated settings screen (see [UiCapture]) as a flat list: toggles,
 * text fields, and the rows or buttons that open something else. Labels come
 * from the text around a control, since layouts rarely tie one to the other.
 */
object ScreenReader {
    enum class Kind { SWITCH, TEXT, ACTION }

    class Entry(
        val kind: Kind,
        /** Child indexes from the screen's root to the control. */
        val path: String,
        val title: String,
        val summary: String?,
        val value: Any?,
        val view: View,
    )

    fun read(root: View): List<Entry> {
        val out = ArrayList<Entry>()
        walk(root, "", Label(), out)
        return out
    }

    /** Finds the control at [path], as given by [Entry.path]. */
    fun find(root: View, path: String): View? {
        var view = root
        if (path.isEmpty()) return view
        for (index in path.split('.')) {
            view = (view as? ViewGroup)?.getChildAt(index.toInt()) ?: return null
        }
        return view
    }

    private class Label {
        var text: String? = null
    }

    private fun walk(view: View, path: String, label: Label, out: MutableList<Entry>) {
        if (view.visibility == View.GONE) return
        when {
            view is CompoundButton ->
                out += Entry(Kind.SWITCH, path, own(view) ?: label.text ?: "Option", null, view.isChecked, view)
            view is EditText ->
                out += Entry(Kind.TEXT, path, view.hint?.toString()?.takeIf { it.isNotBlank() } ?: label.text ?: "Value", null, view.text.toString(), view)
            view is ViewGroup && view.hasOnClickListeners() -> {
                val texts = texts(view)
                out += Entry(Kind.ACTION, path, texts.firstOrNull() ?: describe(view), texts.getOrNull(1), null, view)
            }
            view is TextView && view.hasOnClickListeners() ->
                out += Entry(Kind.ACTION, path, own(view) ?: describe(view), null, null, view)
            view is TextView -> own(view)?.let { label.text = it }
            view is ViewGroup -> for (i in 0 until view.childCount) {
                walk(view.getChildAt(i), if (path.isEmpty()) "$i" else "$path.$i", label, out)
            }
        }
    }

    private fun own(view: TextView): String? = view.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }

    private fun describe(view: View): String = view.contentDescription?.toString()?.takeIf { it.isNotBlank() } ?: "Open"

    private fun texts(group: ViewGroup): List<String> {
        val found = ArrayList<String>()
        fun visit(v: View) {
            if (v is TextView) own(v)?.let(found::add)
            else v.contentDescription?.toString()?.takeIf { it.isNotBlank() }?.let(found::add)
            if (v is ViewGroup) for (i in 0 until v.childCount) visit(v.getChildAt(i))
        }
        visit(group)
        if (found.isEmpty()) group.contentDescription?.toString()?.takeIf { it.isNotBlank() }?.let(found::add)
        return found
    }
}
