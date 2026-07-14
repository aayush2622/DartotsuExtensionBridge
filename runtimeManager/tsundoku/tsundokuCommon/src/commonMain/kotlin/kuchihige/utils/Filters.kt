package kuchihige.utils

import eu.kanade.tachiyomi.source.model.FilterList

/**
 * Returns the first filter in this [FilterList] that matches the given type [T].
 *
 * Example:
 * ```
 * val authorFilter = filters.get<AuthorFilter>()
 * ```
 *
 * @throws NoSuchElementException if no filter of type [T] exists in the list.
 */
inline fun <reified T> FilterList.get(): T = first { it is T } as T
