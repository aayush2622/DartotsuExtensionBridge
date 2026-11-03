package app.shosetsu.lib

import app.shosetsu.lib.Extension.Companion.KEY_CHAPTER_URL
import app.shosetsu.lib.Extension.Companion.KEY_NOVEL_URL
import app.shosetsu.lib.exceptions.HTTPException
import app.shosetsu.lib.exceptions.InvalidMetaDataException
import app.shosetsu.lib.json.ExtensionMetaData
import java.io.IOException
import org.luaj.vm2.LuaError

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

@Deprecated("New name", ReplaceWith("Extension", "app.shosetsu.lib.Extension"))
typealias IExtension = Extension

/**
 * shosetsu-services
 * 30 / May / 2019
 *
 * @author github.com/doomsdayrs
 * @noinspection unused
 */
@Suppress("unused")
interface Extension {
	companion object {
		/** Chapter url key for [expandURL] & [shrinkURL]*/
		const val KEY_CHAPTER_URL: Int = 2

		/** Novel url key for [expandURL] & [shrinkURL]*/
		const val KEY_NOVEL_URL: Int = 1
	}

	/**
	 * This represents a "Page" that the source might have for listing novels.
	 *
	 * Many sources have a singular listing,
	 * which contains filters and queries.
	 *
	 * Some sources have extra pages to display sources, such as
	 * a separate page for latest updates or most viewed
	 */
	class Listing(
		/** Name of this listing */
		val name: String,
		/** If you can continue scrolling for more data or not */
		val isIncrementing: Boolean,
		/**
		 * This gets data from the listing.
		 * Marked as throwing since the lambda is called immediately after it is accessed.
		 */
		@get:Throws(HTTPException::class, LuaError::class, IOException::class)
		val getListing: (data: Map<Int, *>) -> Array<Novel.Info>,
	)

	/** Metadata of the extension */
	@get:Throws(LuaError::class, InvalidMetaDataException::class)
	val exMetaData: ExtensionMetaData

	/** Name of this extension */
	@get:Throws(LuaError::class)
	val name: String

	/**
	 * Base URL of the extension
	 * Used to open up in browser
	 */
	@get:Throws(LuaError::class)
	val baseURL: String

	/**
	 * Image URL of the extension
	 * Used for user recognition
	 */
	@get:Throws(LuaError::class)
	val imageURL: String

	/**
	 * Formatter identification
	 * Separates this from other extensions
	 * Should be as unique as possible
	 */
	@Deprecated("The id is now defined by the metadata", ReplaceWith("exMetaData.id"))
	@get:Throws(LuaError::class)
	val formatterID: Int

	/** If this extension is capable of searching */
	@get:Throws(LuaError::class)
	val hasSearch: Boolean

	/** If this extensions search can be incremented */
	@get:Throws(LuaError::class)
	val isSearchIncrementing: Boolean

	/**
	 * If this extension has cloudflare protection that
	 * requires interception
	 */
	@get:Throws(LuaError::class)
	val hasCloudFlare: Boolean

	/**
	 * Represents the different listings of this extension
	 * @see [Listing]
	 */
	@get:Throws(LuaError::class)
	val listings: Array<Listing>

	/**
	 * Represents the settings model this extension provides
	 */
	@get:Throws(LuaError::class)
	val settingsModel: Array<Filter<*>>

	/**
	 * Represents the filters models to be adjusted on the right
	 */
	@get:Throws(LuaError::class)
	val searchFiltersModel: Array<Filter<*>>

	/** Represents the data type of the chapters that [getPassage] returns */
	@get:Throws(LuaError::class)
	val chapterType: Novel.ChapterType

	/**
	 * Specifies what index should be used when incrementing pages.
	 *
	 * This is useful as some websites follow 0..1..2 and some follow 1..2..3
	 */
	@get:Throws(LuaError::class)
	val startIndex: Int

	/**
	 * Applies a setting a value
	 */
	@Throws(LuaError::class)
	fun updateSetting(id: Int, value: Any?)

	/**
	 * @param data Data that includes query and other filters
	 */
	@Throws(HTTPException::class, IOException::class, LuaError::class)
	fun search(data: Map<Int, *>): Array<Novel.Info>

	/**
	 * Get the passage of a novel
	 * @param chapterURL of the chapter,
	 * will be fed into [expandURL] with [KEY_CHAPTER_URL]
	 *
	 * @return [String] of data corresponding to the [chapterType]
	 */
	@Throws(HTTPException::class, IOException::class, LuaError::class)
	fun getPassage(chapterURL: String): ByteArray

	/**
	 * Using the novel url, Requests for information on the novel
	 * @param novelURL url of novel,
	 * will be fed into [expandURL] with [KEY_NOVEL_URL]
	 *
	 * @param loadChapters option to load chapters or not,
	 * for minor performance options (and debug)
	 */
	@Throws(HTTPException::class, IOException::class, LuaError::class)
	fun parseNovel(novelURL: String, loadChapters: Boolean): Novel.Info

	/**
	 *  @param smallURL URL to enlarge
	 *  @param type Type of url. Either [KEY_CHAPTER_URL] or [KEY_NOVEL_URL]
	 *  @return enlarged URL
	 */
	@Throws(LuaError::class)
	fun expandURL(smallURL: String, type: Int): String

	/**
	 * Access class to shrink data of novels
	 * @param longURL A long url to shrink
	 * @param type Type of url. Either [KEY_CHAPTER_URL] or [KEY_NOVEL_URL]
	 * @return shrunken url
	 */
	@Throws(LuaError::class)
	fun shrinkURL(longURL: String, type: Int): String
}
