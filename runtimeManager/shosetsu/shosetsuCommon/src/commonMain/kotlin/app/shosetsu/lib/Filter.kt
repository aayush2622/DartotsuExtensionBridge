package app.shosetsu.lib

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

/**
 * shosetsu-kotlin-lib
 *
 * @since 2020-01-31
 */
sealed class Filter<T> {
	/**
	 * This is a unique calling card for the specific filter / setting.
	 * If the setting type is ever changed, the ID should be changed
	 */
	abstract val id: Int

	/**
	 * Name of the filer
	 */
	abstract val name: String

	/**
	 * State(s) of the filter stuff
	 */
	abstract var state: T

	@Suppress("IMPLICIT_CAST_TO_ANY")
	override fun toString(): String = "Filter(id='$id', name='$name', state=`${
		if (state is Sequence<*>) {
			state.toString()
		} else {
			state
		}
	}`)"

	/**
	 * Represents a header, used to separate different parts of filters/settings
	 * Includes [Separator]
	 */
	data class Header(override val name: String) : Filter<Unit>() {
		override var state: Unit = Unit
		override val id: Int = -1
	}

	/**
	 * Divides parts of the filters/settings
	 */
	object Separator : Filter<Unit>() {
		override var state: Unit = Unit
		override val id: Int = -1
		override val name: String = ""
	}

	/**
	 * Input for text
	 * Includes [Separator]
	 */
	data class Text(override val id: Int, override val name: String, override var state: String = "") :
		Filter<String>()

	/**
	 * Input for passwords
	 */
	data class Password(
		override val id: Int,
		override val name: String,
		override var state: String = "",
	) : Filter<String>()

	/**
	 * Input for boolean option
	 * Includes [Separator]
	 */
	data class Switch(
		override val id: Int,
		override val name: String,
		override var state: Boolean = false,
	) : Filter<Boolean>()

	/**
	 * Input for boolean option
	 * Includes [Separator]
	 */
	data class Checkbox(
		override val id: Int,
		override val name: String,
		override var state: Boolean = false,
	) : Filter<Boolean>()

	/**
	 * Input for ternary value
	 * Includes [Separator]
	 */
	data class TriState(
		override val id: Int,
		override val name: String,
		override var state: Int = STATE_IGNORED,
	) : Filter<Int>() {
		companion object {
			const val STATE_IGNORED = 0
			const val STATE_INCLUDE = 1
			const val STATE_EXCLUDE = 2
		}
	}

	/**
	 * Input for a choice from a list
	 * Includes [Separator]
	 */
	data class Dropdown(
		override val id: Int,
		override val name: String,
		val choices: List<String>,
		override var state: Int = 0,
	) : Filter<Int>()

	/**
	 * Input for a choice from a list
	 * Includes [Separator]
	 */
	data class RadioGroup(
		override val id: Int,
		override val name: String,
		val choices: List<String>,
		override var state: Int = 0,
	) : Filter<Int>()

	// Grouping

	/**
	 * A collapsable list of filters
	 * Includes [Separator]
	 * @param filters Filters present
	 */
	data class FList(
		override val name: String,
		val filters: List<Filter<*>>,
		override var state: Map<Int, Any> = filters.mapify(),
	) : Filter<Map<Int, Any>>() {
		override val id: Int = -1
	}

	/**
	 * Input for a specific list of filters
	 * Includes [Separator]
	 * @param filters Filters present
	 */
	data class Group<T>(
		override val name: String,
		val filters: List<Filter<T>>,
		override var state: Map<Int, T> = filters.mapifyS(),
	) : Filter<Map<Int, T>>() {
		override val id: Int = -1
	}
}
