package com.lagradost.cloudstream3.plugins

import com.fasterxml.jackson.annotation.JsonProperty
import com.lagradost.cloudstream3.ui.settings.extensions.RepositoryData

data class Repository(
    @JsonProperty("name") val name: String,
    @JsonProperty("description") val description: String?,
    @JsonProperty("manifestVersion") val manifestVersion: Int,
    @JsonProperty("pluginLists") val pluginLists: List<String>,
    @JsonProperty("iconUrl") val iconUrl: String? = null,
)

object RepositoryManager {
    fun getRepositories(): Array<RepositoryData> = emptyArray()

    suspend fun parseRepository(url: String): Repository? = null

    suspend fun addRepository(repository: RepositoryData) {}
}
