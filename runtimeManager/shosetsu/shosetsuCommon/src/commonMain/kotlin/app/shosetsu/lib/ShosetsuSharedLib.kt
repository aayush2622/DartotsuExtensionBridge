package app.shosetsu.lib

import okhttp3.OkHttpClient

/**
 * shosetsu-kotlin-lib
 * 06 / 10 / 2020
 */
object ShosetsuSharedLib {
	/** okhttp HTTP Client used by lib functions. */
	lateinit var httpClient: OkHttpClient

	/**
	 * Used to pretty log.
	 */
	lateinit var logger: (extensionName: String, log: String) -> Unit

	/**
	 * Default headers for shosetsu
	 */
	var shosetsuHeaders = arrayOf<Pair<String, String>>()
}
