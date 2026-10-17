package com.aayush262.dartotsu_extension_bridge.ui

import android.widget.CompoundButton
import android.widget.TextView
import androidx.fragment.app.DialogFragment
import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.aayush262.dartotsu_extension_bridge.ui.ScreenReader.Entry
import com.aayush262.dartotsu_extension_bridge.ui.ScreenReader.Kind

/**
 * An extension's native settings screen as preferences: [list] opens it
 * off-screen and reports its toggles and text fields, following rows that
 * open another sheet (up to [MAX_DEPTH] deep); [save] reopens the screen,
 * sets one control and presses the sheet's save button, so the extension
 * stores the value itself.
 *
 * Keys look like `ui::<sheets>::<control>`: `<sheets>` is the chain of row
 * indexes that leads to the sheet (`-` for the first one, `-/2` for the one
 * its third row opens) and `<control>` the control's path inside it.
 */
class ScreenSettings(
    private val resources: PluginResources,
    private val open: () -> Unit,
) {
    private class Screen(val entries: List<Entry>)

    fun list(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val root = openRoot()
        Logger.log("Settings screen: ${root?.entries?.size ?: "none"} controls", LogLevel.INFO)
        root?.let { explore(it, ROOT, "", 0, out) }
        return out
    }

    fun save(key: String, value: String?): Boolean {
        val parts = key.removePrefix(PREFIX).split(SEPARATOR)
        if (parts.size != 2) return false
        val (sheets, controlPath) = parts
        var screen = openRoot() ?: return false
        for (index in sheets.removePrefix(ROOT).split('/').filter { it.isNotEmpty() }) {
            val row = screen.entries.filter { it.kind == Kind.ACTION }.getOrNull(index.toInt()) ?: return false
            screen = press(row) ?: return false
        }
        if (controlPath.endsWith(CHOICE)) {
            val option = choices(screen, controlPath.removeSuffix(CHOICE)).firstOrNull { it.title == value } ?: return false
            press(option)
            screen.entries.firstOrNull { it.kind == Kind.ACTION && SAVE.containsMatchIn(it.title + " " + it.summary) }
                ?.let { press(it) }
            return true
        }
        val entry = screen.entries.firstOrNull { it.path == controlPath && it.kind != Kind.ACTION } ?: return false
        UiCapture.capture(resources) {
            when (val view = entry.view) {
                is CompoundButton -> view.isChecked = value.toBoolean()
                is TextView -> view.text = value.orEmpty()
            }
        }
        screen.entries.firstOrNull { it.kind == Kind.ACTION && SAVE.containsMatchIn(it.title + " " + it.summary) }
            ?.let { press(it) }
        return true
    }

    private fun explore(screen: Screen, sheets: String, prefix: String, depth: Int, out: MutableList<Map<String, Any?>>) {
        var rowIndex = 0
        val grouped = HashSet<String>()
        if (depth > 0) {
            for (parent in screen.entries.filter { it.kind == Kind.ACTION }.map { parentOf(it.path) }.toSet()) {
                val options = choices(screen, parent)
                if (options.size < 2) continue
                grouped += options.map { it.path }
                out += mapOf(
                    "key" to "$PREFIX$sheets$SEPARATOR$parent$CHOICE", "type" to "list",
                    "title" to prefix.removeSuffix(" › "), "value" to "",
                    "entries" to options.map { it.title }, "entryValues" to options.map { it.title },
                )
            }
        }
        for (entry in screen.entries) {
            if (entry.path in grouped) continue
            when (entry.kind) {
                Kind.SWITCH -> out += mapOf(
                    "key" to "$PREFIX$sheets$SEPARATOR${entry.path}", "type" to "switch",
                    "title" to prefix + entry.title, "value" to entry.value,
                )
                Kind.TEXT -> out += mapOf(
                    "key" to "$PREFIX$sheets$SEPARATOR${entry.path}", "type" to "text",
                    "title" to prefix + entry.title, "value" to entry.value,
                )
                Kind.ACTION -> {
                    val index = rowIndex++
                    if (depth >= MAX_DEPTH || SAVE.containsMatchIn(entry.title + " " + entry.summary)) continue
                    press(entry)?.let { explore(it, "$sheets/$index", "$prefix${entry.title} › ", depth + 1, out) }
                }
            }
        }
    }

    private fun parentOf(path: String) = path.substringBeforeLast('.', "")

    /** Rows under [parent] when they are all that container holds: a list of options, not separate buttons. */
    private fun choices(screen: Screen, parent: String): List<Entry> {
        val rows = screen.entries.filter { it.kind == Kind.ACTION && parentOf(it.path) == parent && !SAVE.containsMatchIn(it.title + " " + it.summary) }
        val container = rows.firstOrNull()?.view?.parent as? android.view.ViewGroup ?: return emptyList()
        return if (container.childCount == rows.size) rows else emptyList()
    }

    private fun openRoot(): Screen? = screens { open() }.firstOrNull()

    /** Presses a row; the sheet it opens, if any. Whatever the row does besides that happens too. */
    private fun press(row: Entry): Screen? = screens { row.view.performClick() }.firstOrNull()

    private fun screens(action: () -> Unit): List<Screen> = try {
        UiCapture.capture(resources) { action() }
            .mapNotNull { f: DialogFragment -> f.view?.let { Screen(ScreenReader.read(it)) } }
    } catch (e: Throwable) {
        Logger.log("Settings screen failed: ${e.stackTraceToString()}", LogLevel.WARNING)
        emptyList()
    }

    companion object {
        private const val PREFIX = "ui::"
        private const val SEPARATOR = "::"
        private const val ROOT = "-"
        private const val CHOICE = "#"
        private const val MAX_DEPTH = 1
        private val SAVE = Regex("\\b(save|apply|confirm|done|ok)\\b", RegexOption.IGNORE_CASE)
        fun isScreenKey(key: String) = key.startsWith(PREFIX)
    }
}
