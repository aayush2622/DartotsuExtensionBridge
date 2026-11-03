package com.lagradost.cloudstream3.plugins

import com.fasterxml.jackson.annotation.JsonProperty
import com.lagradost.cloudstream3.app
import com.lagradost.cloudstream3.ui.settings.extensions.RepositoryData

data class Repository(
    @JsonProperty("name") val name: String,
    @JsonProperty("description") val description: String?,
    @JsonProperty("manifestVersion") val manifestVersion: Int,
    @JsonProperty("pluginLists") val pluginLists: List<String>,
    @JsonProperty("iconUrl") val iconUrl: String? = null,
)

object RepositoryManager {
    private val repositories = java.util.concurrent.CopyOnWriteArrayList<RepositoryData>()

    fun getRepositories(): Array<RepositoryData> = repositories.toTypedArray()

    suspend fun parseRepository(url: String): Repository? = try {
        app.get(url).parsedSafe<Repository>()
    } catch (_: Exception) {
        null
    }

    suspend fun addRepository(repository: RepositoryData) {
        if (repositories.none { it.url == repository.url }) repositories.add(repository)
    }
}
