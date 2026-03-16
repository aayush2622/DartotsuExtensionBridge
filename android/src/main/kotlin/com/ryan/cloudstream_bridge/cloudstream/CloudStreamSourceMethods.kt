package com.ryan.cloudstream_bridge.cloudstream

import android.util.Log
import com.lagradost.cloudstream3.*
import com.lagradost.cloudstream3.utils.*

private const val TAG = "CloudStreamMethods"

class CloudStreamSourceMethods(val provider: MainAPI) {

    suspend fun search(query: String, page: Int): Map<String, Any?> {
        val res = provider.search(query, page) ?: return mapOf("list" to emptyList<Any>(), "hasNextPage" to false)
        return mapOf(
            "list" to res.items.map { it.toMap() },
            "hasNextPage" to res.hasNext  
        )
    }

    suspend fun getDetails(url: String): Map<String, Any?> {
        val res = provider.load(url) ?: return mapOf(
            "title" to null, "url" to url, "cover" to null,
            "description" to null, "episodes" to emptyList<Any>()
        )

        val episodes: List<Map<String, Any?>> = when (res) {
            is TvSeriesLoadResponse -> res.episodes.mapIndexed { i, ep -> episodeToMap(ep, i + 1) }
            is AnimeLoadResponse -> {
                res.episodes.values
                    .flatten()
                    .distinctBy { it.data }
                    .mapIndexed { i, ep -> episodeToMap(ep, i + 1) }
            }
            is MovieLoadResponse -> listOf(
                mapOf(
                    "name" to res.name,
                    "url" to res.dataUrl,  
                    "episodeNumber" to 1.0,
                    "thumbnail" to res.posterUrl,
                    "description" to null,
                    "dateUpload" to null,
                    "scanlator" to null,
                    "filler" to false,
                )
            )
            else -> emptyList()
        }

        return mapOf(
            "title" to res.name,                
            "url" to res.url,
            "cover" to res.posterUrl,           
            "description" to res.plot,          
            "author" to null,
            "artist" to null,
            "genre" to (res.tags ?: emptyList()),
            "episodes" to episodes
        )
    }

    suspend fun loadLinks(data: String): List<Map<String, Any?>> {
        val links = mutableListOf<Map<String, Any?>>()
        val subtitles = mutableListOf<Map<String, Any?>>()

        try {
            provider.loadLinks(
                data,
                false,
                { subtitle ->
                    subtitles.add(
                        mapOf(
                            "file" to subtitle.url,
                            "label" to subtitle.lang
                        )
                    )
                },
                { link ->

                    val finalHeaders = link.headers.takeUnless { it.isNullOrEmpty() }
                        ?: link.referer?.let {
                            val u = java.net.URI(it)
                            val o = "${u.scheme}://${u.host}${if (u.port != -1) ":${u.port}" else ""}"
                            mapOf("Referer" to it, "Origin" to o)
                        }
                        ?: emptyMap()


                    links.add(
                        mapOf(
                            "url" to link.url,
                            "title" to "${link.name} (${qualityLabel(link.quality)})",
                            "quality" to qualityLabel(link.quality),
                            "headers" to finalHeaders,
                            "isM3u8" to (link.type == ExtractorLinkType.M3U8),
                            "subtitles" to subtitles.toList()
                        )
                    )
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "loadLinks failed for $data", e)
        }

        return links
    }

    suspend fun loadLinksStream(data: String, onLinkFound: (Map<String, Any?>) -> Unit) {
        val subtitles = mutableListOf<Map<String, Any?>>()

        try {
            provider.loadLinks(
                data,
                false,
                { subtitle ->
                    subtitles.add(
                        mapOf(
                            "file" to subtitle.url,
                            "label" to subtitle.lang
                        )
                    )
                },
                { link ->

                    val finalHeaders = link.headers.takeUnless { it.isNullOrEmpty() }
                        ?: link.referer?.let {
                            val u = java.net.URI(it)
                            val o = "${u.scheme}://${u.host}${if (u.port != -1) ":${u.port}" else ""}"
                            mapOf("Referer" to it, "Origin" to o)
                        }
                        ?: emptyMap()

                    val linkMap = mapOf(
                        "url" to link.url,
                        "title" to "${link.name} (${qualityLabel(link.quality)})",
                        "quality" to qualityLabel(link.quality),
                        "headers" to finalHeaders,
                        "isM3u8" to (link.type == ExtractorLinkType.M3U8),
                        "subtitles" to subtitles.toList()
                    )
                    
                    onLinkFound(linkMap)
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "loadLinksStream failed for $data", e)
        }
    }

    private fun qualityLabel(quality: Int): String = when {
        quality <= 0 -> "Unknown"
        quality >= 2160 -> "4K"
        quality >= 1080 -> "1080p"
        quality >= 720 -> "720p"
        quality >= 480 -> "480p"
        quality >= 360 -> "360p"
        else -> "${quality}p"
    }
}


fun SearchResponse.toMap(): Map<String, Any?> {
    return mapOf(
        "title" to name,          
        "url" to url,
        "apiName" to apiName,
        "cover" to posterUrl,     
        "type" to type?.ordinal,
        "id" to id,
        "quality" to quality?.ordinal,
        "score" to score?.toInt(100)
    )
}

fun episodeToMap(ep: Episode, fallbackNumber: Int): Map<String, Any?> {
    val rawNum = ep.episode?.toDouble() ?: fallbackNumber.toDouble()
    return mapOf(
        "name" to ep.name,
        "url" to ep.data,              
        "episodeNumber" to rawNum,     
        "thumbnail" to ep.posterUrl,
        "description" to ep.description,
        "dateUpload" to ep.date?.toString(),
        "scanlator" to null,
        "filler" to false,
    )
}
