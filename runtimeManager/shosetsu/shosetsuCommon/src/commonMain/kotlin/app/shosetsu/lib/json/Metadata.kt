package app.shosetsu.lib.json

import app.shosetsu.lib.Version
import java.io.File
import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * @param id ID
 * @param version 3 index array
 * @param libVersion Version of the library this extension was made for
 * @param author Author / Creator of this extension
 * @param repo Repository URL that this extension is connected with
 * @param stringDep
 */
@Serializable
data class ExtensionMetaData(
	@SerialName(J_ID)
	val id: Int,
	@SerialName(J_VERSION)
	val version: Version,
	@SerialName(J_LIB_VERSION)
	val libVersion: Version,
	@SerialName(J_AUTHOR)
	val author: String = "",
	@SerialName(J_REPO)
	val repo: String = "",
	@SerialName(J_DEP)
	val stringDep: List<String> = listOf(),
) {
	val dependencies: Map<String, Version> by lazy {
		val v = stringDep.map { value -> value.split(">=").let { dep -> dep.first() to dep[1] } }
		val map = HashMap<String, Version>()
		v.forEach { (dep, ver) ->
			map[dep] = Version(ver)
		}
		map
	}
}

@Serializable
data class LibraryMetaData(
	@SerialName(J_VERSION)
	val version: Version,
	@SerialName(J_AUTHOR)
	val author: String = "",
	@SerialName(J_REPO)
	val repo: String = "",
	@SerialName(J_DEP)
	val stringDep: List<String> = listOf(),
)

@Serializable
data class StyleMetaData(
	@SerialName(J_ID)
	val id: Int,
	@SerialName(J_NAME)
	val name: String,
	@SerialName(J_VERSION)
	val version: Version,
	@SerialName(J_DESCRIPTION)
	val description: String = "",
	@SerialName(J_CHANGELOG)
	val changeLog: String = "",
	@SerialName(J_AUTHOR)
	val author: String = "",
	@SerialName(J_SUPPORTED)
	val supported: List<Int> = emptyList(),
) {
	companion object {
		fun extract(sourceFile: File) = extract(sourceFile.readText())

		fun extract(sourceFile: Path) = extract(sourceFile.readText())

		fun extract(sourceFile: String): StyleMetaData {
			val line = sourceFile.lines().first().trim()
			if (!line.startsWith("/*")) {
				throw IllegalArgumentException("Metadata section must be in the first line and start with /*")
			}
			if (!line.endsWith("*/")) {
				throw IllegalArgumentException("Metadata section must be in the first line and end with */")
			}
			val section = line.substring(2, line.length - 2).trim()
			return Json.decodeFromString(section)
		}
	}
}

@Serializable
data class JavaScriptMetaData(
	@SerialName(J_ID)
	val id: Int,
	@SerialName(J_NAME)
	val name: String,
	@SerialName(J_VERSION)
	val version: Version,
	@SerialName(J_DESCRIPTION)
	val description: String = "",
	@SerialName(J_CHANGELOG)
	val changeLog: String = "",
	@SerialName(J_AUTHOR)
	val author: String = "",
	@SerialName(J_SUPPORTED)
	val supported: List<Int> = emptyList(),
) {
	companion object {
		fun extract(sourceFile: File) = extract(sourceFile.readText())

		fun extract(sourceFile: Path) = extract(sourceFile.readText())

		fun extract(sourceFile: String): JavaScriptMetaData {
			val line = sourceFile.lines().first().trim()
			if (!line.startsWith("//")) {
				throw IllegalArgumentException("Metadata section must be in the first line and start with //")
			}
			val section = line.substring(2).trimStart()
			return Json.decodeFromString(section)
		}
	}
}
