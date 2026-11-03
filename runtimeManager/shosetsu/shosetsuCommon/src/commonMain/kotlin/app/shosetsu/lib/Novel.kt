@file:Suppress("MemberVisibilityCanBePrivate")

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
 * Placeholder class to help organize all the various novel related data.
 *
 * @since 2020-01-31
 * @author github.com/doomsdayrs
 */
class Novel {
	/**
	 * Represents a chapter of a novel.
	 * These are included in [Novel.Info].
	 *
	 * @param release Tell the user what date the chapter was released on. Can be empty.
	 * @param title Title of the chapter, should not be empty.
	 * @param link Link to the chapter, should be shrunk.
	 * @param order Absolute order of a chapter, as declared by a site.
	 *  Used for sorting.
	 *  For example. Let us say a site has 10 chapters, listed as such:
	 *  1, 2, 3, 5, 6, 10, 8, 9.
	 *  While the chapters are out of order, it is okay. These will be numbered:
	 *  0, 1, 2, 3, 4, 5, 6, 7; in their [order] value.
	 *  @param sourceId Unique id of a chapter provided by a site.
	 *  Will be used to match in case link or order changes.
	 *
	 *  @see Novel.Info
	 */
	data class Chapter(
		var release: String = "",
		var title: String = "",
		var link: String = "",
		var order: Double = 0.0,
		var sourceId: Int? = null,
	)

	/**
	 * Status of a novel.
	 */
	enum class Status(val title: String, val key: Int) {
		/**
		 * Novel is still being updated / translated / published.
		 */
		PUBLISHING("Publishing", 0),

		/**
		 * Novel has been finished updating / translating / publishing.
		 */
		COMPLETED("Completed", 1),

		/**
		 * Novel is on hiatus from updating / translating / publishing.
		 */
		PAUSED("Paused", 2),

		/**
		 * Status of the novel cannot be determined.
		 *  Should be used as default if unknown.
		 */
		UNKNOWN("Unknown", -1),
		;

		override fun toString() = "NovelStatus($title)"

		companion object {
			fun fromInt(key: Int): Status = when (key) {
				0 -> PUBLISHING
				1 -> COMPLETED
				2 -> PAUSED
				else -> UNKNOWN
			}
		}
	}

	/**
	 * Information about a novel.
	 *
	 * @param title Title of the novel, should not be empty.
	 * @param alternativeTitles Alternative titles of a given novel.
	 *  Useful for translated novels.
	 * @param imageURL Image URL of the novel, can be empty.
	 * @param language ISO 639-2/T language code of the novel, should not be empty.
	 * @param description Description of the novel, should not be empty.
	 * @param status Status of the novel, defaulted as [Novel.Status.UNKNOWN]
	 * @param tags Tags that the novel has.
	 * @param genres Genres the novel applies too.
	 * @param authors Authors of the novel.
	 * @param artists Artists of the novel.
	 * @param chapters Chapters of the novel.
	 * @param chapterCount Chapter count of the novel.
	 * @param wordCount Word count of the novel.
	 * @param commentCount Comment count of the novel.
	 * @param viewCount View count of the novel.
	 * @param favoriteCount Favorite count of the novel.
	 *
	 * @see Novel.Chapter
	 */
	@Suppress("ArrayInDataClass")
	data class Info(
		var title: String = "",
		var alternativeTitles: Array<String> = arrayOf(),
		var link: String = "",
		var imageURL: String = "",
		var language: String = "",
		var description: String = "",
		var status: Status = Status.UNKNOWN,
		var tags: Array<String> = arrayOf(),
		var genres: Array<String> = arrayOf(),
		var authors: Array<String> = arrayOf(),
		var artists: Array<String> = arrayOf(),
		var chapters: Array<Chapter> = arrayOf(),
		var chapterCount: Int? = null,
		var wordCount: Int? = null,
		var commentCount: Int? = null,
		var viewCount: Int? = null,
		var favoriteCount: Int? = null,
	)

	/**
	 * Chapter type that an extension provides.
	 */
	enum class ChapterType(val key: Int, val fileExtension: String) {
		/** Strings with no formatting */
		STRING(0, "txt"),

		/** HTML pages */
		HTML(1, "html"),
		;

		companion object {
			fun valueOf(key: Int): ChapterType = when (key) {
				1 -> HTML
				else -> STRING
			}
		}
	}
}
