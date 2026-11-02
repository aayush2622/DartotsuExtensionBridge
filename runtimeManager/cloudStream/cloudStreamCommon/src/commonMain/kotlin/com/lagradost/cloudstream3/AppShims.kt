package com.lagradost.cloudstream3

import android.content.Context

abstract class UiText {
    abstract fun asString(context: Context?): String
    fun asStringNull(context: Context?): String? = asString(context)
    class StringValue(val value: String) : UiText() {
        override fun asString(context: Context?) = value
    }
}

fun txt(s: String?): UiText = UiText.StringValue(s ?: "")

enum class VideoWatchState {
    None,
    Watched
}

data class ResultEpisode(
    val headerName: String,
    val name: String?,
    val poster: String?,
    val episode: Int,
    val seasonIndex: Int?,
    val season: Int?,
    val data: String,
    val apiName: String,
    val id: Int,
    val index: Int,
    val position: Long = 0,
    val duration: Long = 0,
    val score: Score? = null,
    val description: String? = null,
    val isFiller: Boolean? = null,
    val tvType: TvType = TvType.Anime,
    val parentId: Int = 0,
    val videoWatchState: VideoWatchState = VideoWatchState.None,
    val totalEpisodeIndex: Int? = null,
    val airDate: Long? = null,
    val runTime: Int? = null,
)

data class SubtitleData(
    val name: String,
    val url: String,
    val origin: String? = null,
    val headers: Map<String, String> = mapOf()
)

data class LinkLoadingResult(
    val links: List<com.lagradost.cloudstream3.utils.ExtractorLink>,
    val subs: List<SubtitleData>,
    val syncData: HashMap<String, String>
)
