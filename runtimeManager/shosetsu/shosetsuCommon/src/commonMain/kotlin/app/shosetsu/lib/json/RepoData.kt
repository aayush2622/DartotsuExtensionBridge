package app.shosetsu.lib.json

import app.shosetsu.lib.ExtensionType
import app.shosetsu.lib.Version
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 17 / 10 / 2020
 *
 * Represents an extension on the repository,
 * listed as "scripts" in the index
 *
 * @param id Identification of this extension, this should always be unique
 * @param name Name of the extension that is presentable to the user
 * @param fileName FileName of the extension
 * @param imageURL Image URL for this extension, for visual identification
 * @param lang String identification of the language via (ISO 639-1) standard
 * @param version Version of this extension
 * @param libVersion Version the extension is compatible with
 * @param md5 MD5 coding of the extension, for security checking
 * @param type Type of extension.
 */
@Serializable
data class RepoExtension(
	@SerialName(J_ID)
	val id: Int,
	@SerialName(J_NAME)
	val name: String,
	@SerialName(J_FILE_NAME)
	val fileName: String,
	@SerialName(J_IMAGE_URL)
	val imageURL: String,
	@SerialName(J_LANGUAGE)
	val lang: String,
	@SerialName(J_VERSION)
	val version: Version,
	@SerialName(J_LIB_VERSION)
	val libVersion: Version,
	@SerialName(J_MD5)
	val md5: String = "",
	@SerialName(J_EXTENSION_TYPE)
	val type: ExtensionType = ExtensionType.LuaScript,
)

/**
 * 17 / 10 / 2020
 *
 * Represents a library listed in `libraries` within the repository index
 *
 * @param name Name of the library, this is always the same as the filename
 *
 * @param version Version of the library
 *
 * @param url Remote URL to download the library, useful for different licenses.
 * Must be an HTTPS URL, HTTP will conflict with android security rules.
 *
 * @param hash SHA256 Hash of the remote file, to prevent attacks.
 */
@Serializable
data class RepoLibrary(
	@SerialName(J_NAME)
	val name: String,
	@SerialName(J_VERSION)
	val version: Version,
	@SerialName(J_URL)
	val url: String? = null,
	@SerialName(J_HASH)
	val hash: String? = null,
)

/**
 * 17 / 10 / 2020
 *
 * Represents a style listed in `styles` within the repository index
 *
 * @param id Primary key, should be completely unique
 * @param name Name of style sheet, this is shown to users
 * @param fileName Filename of the css file, used internally by shosetsu
 * @param description Description of the style
 * @param changeLog Description of recent changes
 * @param authors Authors who created this
 * @param supported List of explicitly supported extensions
 * @param hasExample States if this has an example HTML to show the user
 * @param hasJavaScript Does this style have custom javascript that can be loaded
 */
@Serializable
data class RepoStyle(
	@SerialName(J_ID)
	val id: Int,
	@SerialName(J_NAME)
	val name: String,
	@SerialName(J_FILE_NAME)
	val fileName: String,
	@SerialName(J_VERSION)
	val version: Version,
	@SerialName(J_DESCRIPTION)
	val description: String = "",
	@SerialName(J_CHANGELOG)
	val changeLog: String = "",
	@SerialName(J_AUTHORS)
	val authors: List<Int> = emptyList(),
	@SerialName(J_SUPPORTED)
	val supported: List<Int> = emptyList(),
	@SerialName(J_JAVASCRIPT)
	val hasJavaScript: Boolean = false,
	@SerialName(J_EXAMPLE)
	val hasExample: Boolean = false,
	@SerialName(J_HASH)
	val hash: String? = null,
	@SerialName(J_JS_HASH)
	val javaScriptHash: String? = null,
	@SerialName(J_EXAMPLE_HASH)
	val exampleHash: String? = null,
)

/**
 * 17 / 10 / 2020
 *
 * Represents javascript listed in `js` within the repository index
 *
 * @param id Primary key, should be completely unique
 * @param name Name of the js file, this is shown to users
 * @param fileName Filename of the js file, used internally by shosetsu
 * @param description Description of the effects of the js
 * @param changeLog Description of recent changes
 * @param authors Authors who created this
 * @param supported List of explicitly supported extensions
 * @param hasExample States if this has an example HTML to show the user
 */
@Serializable
data class RepoJavaScript(
	@SerialName(J_ID)
	val id: Int,
	@SerialName(J_NAME)
	val name: String,
	@SerialName(J_FILE_NAME)
	val fileName: String,
	@SerialName(J_VERSION)
	val version: Version,
	@SerialName(J_DESCRIPTION)
	val description: String = "",
	@SerialName(J_CHANGELOG)
	val changeLog: String = "",
	@SerialName(J_AUTHORS)
	val authors: List<Int> = emptyList(),
	@SerialName(J_SUPPORTED)
	val supported: List<Int> = emptyList(),
	@SerialName(J_EXAMPLE)
	val hasExample: Boolean = false,
	@SerialName(J_HASH)
	val hash: String? = null,
	@SerialName(J_EXAMPLE_HASH)
	val exampleHash: String? = null,
)

/**
 * 17 / 10 / 2020
 *
 * Represents an author.
 *
 * These are weak entities that are dependent on what they are attached to.
 *
 * @param id Unique id of the author
 * @param name Your name
 * @param description Description of the author.
 * @param imageURL A friendly image to display to users
 * @param website Website of the author
 */
@Serializable
data class RepoAuthor(
	@SerialName(J_ID)
	val id: Int,
	@SerialName(J_NAME)
	val name: String,
	@SerialName(J_DESCRIPTION)
	val description: String = "",
	@SerialName(J_IMAGE_URL)
	val imageURL: String = "",
	@SerialName(J_WEBSITE)
	val website: String = "",
)
