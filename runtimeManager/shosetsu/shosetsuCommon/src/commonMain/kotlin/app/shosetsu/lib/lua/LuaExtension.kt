package app.shosetsu.lib.lua

import app.shosetsu.lib.*
import app.shosetsu.lib.exceptions.InvalidFilterIDException
import app.shosetsu.lib.exceptions.InvalidMetaDataException
import app.shosetsu.lib.exceptions.MissingOrInvalidKeysException
import app.shosetsu.lib.exceptions.VersionMismatchException
import app.shosetsu.lib.json.ExtensionMetaData
import java.io.File
import java.nio.file.Path
import kotlin.io.path.name
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import org.luaj.vm2.LuaError
import org.luaj.vm2.LuaString.EMPTYSTRING
import org.luaj.vm2.LuaTable
import org.luaj.vm2.LuaValue
import org.luaj.vm2.LuaValue.*
import org.luaj.vm2.lib.jse.CoerceJavaToLua.coerce
import org.luaj.vm2.lib.jse.CoerceLuaToJava

/*
 * This file is part of shosetsu-services.
 * shosetsu-services is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * shosetsu-services is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * You should have received a copy of the GNU General Public License
 * along with shosetsu-services.  If not, see https://www.gnu.org/licenses/.
 */

/**
 * shosetsu-kotlin-lib
 * 16 / 01 / 2020
 *
 * @param content extension script
 * @param debugName name to use debug
 */
class LuaExtension
@Throws(
	MissingOrInvalidKeysException::class,
	InvalidFilterIDException::class,
	LuaError::class,
)
constructor(
	@Suppress("MemberVisibilityCanBePrivate")
	val content: String,
	debugName: String = "unknown",
) : Extension {
	companion object {
		/**
		 * Values that may not be present
		 */
		val defaults: Map<String, LuaValue> = mapOf(
			KEY_IMAGE_URL to EMPTYSTRING,
			KEY_HAS_CLOUD_FLARE to FALSE,
			KEY_HAS_SEARCH to TRUE,
			KEY_IS_SEARCH_INC to TRUE,
			KEY_SEARCH_FILTERS to LuaTable(),
			KEY_SETTINGS to LuaTable(),
			KEY_CHAPTER_TYPE to coerce(Novel.ChapterType.STRING),
			KEY_START_INDEX to ONE,
		)

		/**
		 * Values that must be present
		 */
		val hardKeys: Map<String, Int> = mapOf(
			KEY_NAME to TSTRING,
			KEY_LISTINGS to TTABLE,
			KEY_GET_PASSAGE to TFUNCTION,
			KEY_PARSE_NOVEL to TFUNCTION,
			KEY_EXPAND_URL to TFUNCTION,
			KEY_SHRINK_URL to TFUNCTION,
		)

		/**
		 * What is unique about soft keys is they are conditional on the soft key beforehand
		 * IE, if hasSearch is false, then search does not need to be present in script
		 */
		val softKeys: Map<String, Pair<Pair<String, Int>, (LuaValue) -> Boolean>> =
			mapOf(
				KEY_HAS_SEARCH to Pair(
					first = Pair(KEY_SEARCH, TFUNCTION),
					second = { v -> (v == TRUE) },
				),
				KEY_SETTINGS to Pair(
					first = Pair(KEY_UPDATE_SETTING, TFUNCTION),
					second = { v -> (v as LuaTable).length() != 0 },
				),
			)

		private fun tableToFilters(table: LuaTable): Array<Filter<*>> =
			table.keys().map { table[it] }.filter { !it.isnil() }
				.map {
					CoerceLuaToJava.coerce(
						it,
						Any::class.java,
					) as Filter<*>
				}.toTypedArray()
	}

	constructor(file: File) : this(file.readText(), file.name)
	constructor(file: Path) : this(file.readText(), file.name)

	/**
	 * Returns the metadata that is at the header of the extension
	 */
	override val exMetaData: ExtensionMetaData = try {
		Json.decodeFromString(extractMetaDataSection(content))
	} catch (e: Exception) {
		throw InvalidMetaDataException(debugName, e)
	}

	private val source: LuaTable

	init {
		if (!Version.isDependencySatisfied(requestedVersion = exMetaData.libVersion)) {
			throw InvalidMetaDataException(
				debugName,
				VersionMismatchException(exMetaData.libVersion, KOTLIN_LIB_VERSION),
			)
		}

		val globals = shosetsuGlobals()
		val l = try {
			globals.load(content, "ext($debugName)")!!
		} catch (e: Error) {
			throw e
		}
		source = l.call() as LuaTable

		// If the modified default value doesn't exist, it assigns the default
		defaults.filter { source[it.key].isnil() }
			.forEach { source[it.key] = it.value }

		// If any required value is not found,
		// it throws an NullPointerException
		with(
			hardKeys.filter { expected ->
				source.get(expected.key).type() != expected.value
			}.map { it.key },
		) {
			if (isNotEmpty()) {
				throw MissingOrInvalidKeysException(
					debugName,
					this,
				)
			}
		}

		// If any of the softKeys matching their condition of requirement
		// are not found, it throws an NullPointerException
		with(
			softKeys.filter {
				val t = it.value.first
				if (it.value.second(source[it.key])) {
					source.get(t.first).type() != t.second
				} else {
					false
				}
			}.map { it.value.first.first },
		) {
			if (isNotEmpty()) {
				throw MissingOrInvalidKeysException(
					debugName,
					this,
				)
			}
		}

		// Ensure no reserved filter IDs are used
		tableToFilters(source[KEY_SEARCH_FILTERS] as LuaTable).let { table ->
// 			println(table.contentDeepToString())
			listOf(QUERY_INDEX, PAGE_INDEX).forEach { reserved ->
				if (table.any { it.id == reserved }) {
					throw InvalidFilterIDException(debugName, reserved)
				}
			}
		}
	}

	override val name: String by lazy {
		source[KEY_NAME].tojstring()
	}
	override val baseURL: String by lazy {
		source[KEY_BASE_URL].tojstring()
	}
	override val formatterID by lazy {
		source[KEY_ID].toint()
	}
	override val imageURL: String by lazy {
		source[KEY_IMAGE_URL].tojstring()
	}
	override val hasCloudFlare by lazy {
		source[KEY_HAS_CLOUD_FLARE].toboolean()
	}
	override val hasSearch by lazy {
		source[KEY_HAS_SEARCH].toboolean()
	}
	override val isSearchIncrementing: Boolean by lazy {
		source[KEY_IS_SEARCH_INC].toboolean()
	}

	override val startIndex: Int by lazy {
		source[KEY_START_INDEX].toint()
	}

	override val listings: Array<Extension.Listing> by lazy {
		coerceLuaToJava<Array<Extension.Listing>>(source[KEY_LISTINGS])
	}

	override val searchFiltersModel: Array<Filter<*>> by lazy {
		tableToFilters(source[KEY_SEARCH_FILTERS] as LuaTable)
	}

	override val chapterType: Novel.ChapterType by lazy {
		coerceLuaToJava<Novel.ChapterType>(source[KEY_CHAPTER_TYPE])
	}

	override val settingsModel: Array<Filter<*>> by lazy {
		tableToFilters(source[KEY_SETTINGS] as LuaTable)
	}

	override fun updateSetting(id: Int, value: Any?) {
		source[KEY_UPDATE_SETTING].takeIf { it.type() == TFUNCTION }
			?.call(valueOf(id), coerce(value))
			?: return
	}

	override fun getPassage(chapterURL: String): ByteArray {
		val result = source[KEY_GET_PASSAGE].call(chapterURL).checkstring()
		return when (chapterType) {
			Novel.ChapterType.STRING -> result.tojstring().encodeToByteArray()
			Novel.ChapterType.HTML -> result.tojstring().encodeToByteArray()
		}
	}

	override fun parseNovel(novelURL: String, loadChapters: Boolean): Novel.Info = coerceLuaToJava(
		source[KEY_PARSE_NOVEL].call(
			valueOf(novelURL),
			valueOf(loadChapters),
		),
	)

	override fun search(data: Map<Int, *>): Array<Novel.Info> =
		coerceLuaToJava(source[KEY_SEARCH].call(data.toLua()))

	override fun expandURL(smallURL: String, type: Int): String {
		val f = source[KEY_EXPAND_URL]
		if (f.type() != TFUNCTION) return smallURL
		return f.call(valueOf(smallURL), valueOf(type)).tojstring()
	}

	override fun shrinkURL(longURL: String, type: Int): String {
		val f = source[KEY_SHRINK_URL]
		if (f.type() != TFUNCTION) return longURL
		return f.call(valueOf(longURL), valueOf(type)).tojstring()
	}
}
