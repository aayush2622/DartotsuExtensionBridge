package com.aayush262.dartotsu_extension_bridge

import com.google.gson.Gson
import eu.kanade.tachiyomi.animesource.model.AnimeFilter
import eu.kanade.tachiyomi.animesource.model.AnimeFilterList
import eu.kanade.tachiyomi.source.model.Filter
import eu.kanade.tachiyomi.source.model.FilterList

private val filterJsonGson = Gson()

fun AnimeFilterList.toFilterJson(): String = filterJsonGson.toJson(map { it.toGenericMap() })

fun AnimeFilterList.applyFilterJson(json: String) {
    val states = decodeFilterStates(json)
    forEachIndexed { index, filter -> filter.applyGenericState(states.getOrNull(index)) }
}

fun FilterList.toFilterJson(): String = filterJsonGson.toJson(map { it.toGenericMap() })

fun FilterList.applyFilterJson(json: String) {
    val states = decodeFilterStates(json)
    forEachIndexed { index, filter -> filter.applyGenericState(states.getOrNull(index)) }
}

@Suppress("UNCHECKED_CAST")
private fun decodeFilterStates(json: String): List<Map<String, Any?>> =
    (filterJsonGson.fromJson(json, List::class.java) as? List<Map<String, Any?>>).orEmpty()

private fun AnimeFilter<*>.toGenericMap(): Map<String, Any?> = when (this) {
    is AnimeFilter.Header -> mapOf("type" to "header", "name" to name)
    is AnimeFilter.Separator -> mapOf("type" to "separator", "name" to "")
    is AnimeFilter.Text -> mapOf("type" to "text", "name" to name, "textValue" to state)
    is AnimeFilter.CheckBox -> mapOf("type" to "checkbox", "name" to name, "checkBoxValue" to state)
    is AnimeFilter.TriState -> mapOf("type" to "tri_state", "name" to name, "triState" to state)
    is AnimeFilter.Select<*> -> mapOf(
        "type" to "select", "name" to name, "selectIndex" to state,
        "selectOptions" to values.map { it.toString() },
    )
    is AnimeFilter.Sort -> mapOf(
        "type" to "sort", "name" to name,
        "sortIndex" to state?.index, "sortAscending" to state?.ascending,
        "sortOptions" to values.toList(),
    )
    is AnimeFilter.Group<*> -> mapOf(
        "type" to "group", "name" to name,
        "group" to state.filterIsInstance<AnimeFilter<*>>().map { it.toGenericMap() },
    )
    else -> mapOf("type" to "header", "name" to name)
}

@Suppress("UNCHECKED_CAST")
private fun AnimeFilter<*>.applyGenericState(state: Map<String, Any?>?) {
    state ?: return
    when (this) {
        is AnimeFilter.Text -> (state["textValue"] as? String)?.let { this.state = it }
        is AnimeFilter.CheckBox -> (state["checkBoxValue"] as? Boolean)?.let { this.state = it }
        is AnimeFilter.TriState -> (state["triState"] as? Double)?.let { this.state = it.toInt() }
        is AnimeFilter.Select<*> -> (state["selectIndex"] as? Double)?.let { this.state = it.toInt() }
        is AnimeFilter.Sort -> {
            val index = (state["sortIndex"] as? Double)?.toInt()
            val ascending = state["sortAscending"] as? Boolean
            if (index != null && ascending != null) {
                this.state = AnimeFilter.Sort.Selection(index, ascending)
            }
        }
        is AnimeFilter.Group<*> -> {
            val entries = this.state.filterIsInstance<AnimeFilter<*>>()
            val children = (state["group"] as? List<Map<String, Any?>>).orEmpty()
            entries.forEachIndexed { index, child -> child.applyGenericState(children.getOrNull(index)) }
        }
        else -> {}
    }
}

private fun Filter<*>.toGenericMap(): Map<String, Any?> = when (this) {
    is Filter.Header -> mapOf("type" to "header", "name" to name)
    is Filter.Separator -> mapOf("type" to "separator", "name" to "")
    is Filter.Text -> mapOf("type" to "text", "name" to name, "textValue" to state)
    is Filter.CheckBox -> mapOf("type" to "checkbox", "name" to name, "checkBoxValue" to state)
    is Filter.TriState -> mapOf("type" to "tri_state", "name" to name, "triState" to state)
    is Filter.Select<*> -> mapOf(
        "type" to "select", "name" to name, "selectIndex" to state,
        "selectOptions" to values.map { it.toString() },
    )
    is Filter.Sort -> mapOf(
        "type" to "sort", "name" to name,
        "sortIndex" to state?.index, "sortAscending" to state?.ascending,
        "sortOptions" to values.toList(),
    )
    is Filter.Group<*> -> mapOf(
        "type" to "group", "name" to name,
        "group" to state.filterIsInstance<Filter<*>>().map { it.toGenericMap() },
    )
    else -> mapOf("type" to "header", "name" to name)
}

@Suppress("UNCHECKED_CAST")
private fun Filter<*>.applyGenericState(state: Map<String, Any?>?) {
    state ?: return
    when (this) {
        is Filter.Text -> (state["textValue"] as? String)?.let { this.state = it }
        is Filter.CheckBox -> (state["checkBoxValue"] as? Boolean)?.let { this.state = it }
        is Filter.TriState -> (state["triState"] as? Double)?.let { this.state = it.toInt() }
        is Filter.Select<*> -> (state["selectIndex"] as? Double)?.let { this.state = it.toInt() }
        is Filter.Sort -> {
            val index = (state["sortIndex"] as? Double)?.toInt()
            val ascending = state["sortAscending"] as? Boolean
            if (index != null && ascending != null) {
                this.state = Filter.Sort.Selection(index, ascending)
            }
        }
        is Filter.Group<*> -> {
            val entries = this.state.filterIsInstance<Filter<*>>()
            val children = (state["group"] as? List<Map<String, Any?>>).orEmpty()
            entries.forEachIndexed { index, child -> child.applyGenericState(children.getOrNull(index)) }
        }
        else -> {}
    }
}
