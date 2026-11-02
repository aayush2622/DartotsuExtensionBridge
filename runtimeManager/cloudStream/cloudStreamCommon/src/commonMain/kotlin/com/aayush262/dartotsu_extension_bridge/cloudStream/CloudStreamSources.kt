package com.aayush262.dartotsu_extension_bridge.cloudStream

import com.lagradost.cloudstream3.APIHolder.allProviders
import com.lagradost.cloudstream3.MainAPI

object CloudStreamSources {
    private fun describe(provider: MainAPI): Map<String, Any?> = mapOf(
        "id" to provider.name,
        "name" to provider.name,
        "lang" to provider.lang,
        "supportsLatest" to true,
        "sourcePlugin" to provider.sourcePlugin,
        "baseUrl" to provider.mainUrl,
        "iconUrl" to "https://avatars.githubusercontent.com/u/110591699?s=48&v=4",
        "itemType" to 1,
        "version" to ExtensionLoader.plugins[provider.sourcePlugin]?.manifest?.version.toString(),
    )

    fun all(): List<Map<String, Any?>> = allProviders.toList().map(::describe)

    fun of(path: String): List<Map<String, Any?>> =
        allProviders.toList().filter { it.sourcePlugin == path }.map(::describe)
}
