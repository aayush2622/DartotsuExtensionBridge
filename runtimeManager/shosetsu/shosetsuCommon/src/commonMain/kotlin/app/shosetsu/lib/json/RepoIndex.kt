package app.shosetsu.lib.json

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * shosetsu-kotlin-lib
 * 17 / 10 / 2020
 * @param libraries Libraries used by the repository
 * @param extensions Extensions listed in this repository
 * @param styles Styles listed in this repository
 * @param scripts Javascript scripts that a user can load
 */
@Serializable
data class RepoIndex(
	@SerialName(J_AUTHORS)
	val authors: List<RepoAuthor> = emptyList(),
	@SerialName(LIBS_KEY)
	val libraries: List<RepoLibrary> = emptyList(),
	@SerialName(EXTS_KEY)
	val extensions: List<RepoExtension> = emptyList(),
	@SerialName(STYL_KEY)
	val styles: List<RepoStyle> = emptyList(),
	@SerialName(SCRT_KEY)
	val scripts: List<RepoJavaScript> = emptyList(),
) {
	companion object {
		const val LIBS_KEY = "libraries"
		const val EXTS_KEY = "scripts"
		const val STYL_KEY = "styles"
		const val SCRT_KEY = "js"

		/**
		 * JSON parser for [RepoIndex], ensuring that behavior is consistent
		 */
		val repositoryJsonParser: Json =
			Json {
				encodeDefaults = true
				ignoreUnknownKeys = true
			}
	}
}
