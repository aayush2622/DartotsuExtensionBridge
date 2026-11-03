package app.shosetsu.lib

import com.google.common.io.Resources

/*
 * This file is part of shosetsu-kotlin-lib.
 * shosetsu-kotlin-lib is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * shosetsu-kotlin-lib is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * You should have received a copy of the GNU General Public License
 * along with shosetsu-kotlin-lib.  If not, see <https://www.gnu.org/licenses/>.
 */

fun List<Filter<*>>.mapify(): Map<Int, Any> = HashMap<Int, Any>().apply hasMap@{
	this@mapify.forEach {
		when (val state = it.state) {
			is Map<*, *> -> {
				@Suppress("UNCHECKED_CAST")
				this.putAll(state as Map<out Int, Any>)
			}

			else -> {
				this[it.id] = state!!
			}
		}
	}
}

fun <T> List<Filter<T>>.mapifyS(): Map<Int, T> = HashMap<Int, T>().apply hasMap@{
	this@mapifyS.forEach {
		when (val state = it.state) {
			is Map<*, *> -> {
				@Suppress("UNCHECKED_CAST")
				this.putAll(state as Map<out Int, T>)
			}

			else -> {
				this[it.id] = state
			}
		}
	}
}

/**
 * Reads a resource file
 */
fun loadResource(file: String): String = Resources.getResource(file).readText()
