package eu.kanade.tachiyomi.torrentutils

import com.aayush262.dartotsu_extension_bridge.FlutterBridge
import com.google.gson.Gson
import eu.kanade.tachiyomi.torrentutils.model.TorrentFile
import eu.kanade.tachiyomi.torrentutils.model.TorrentInfo

actual object TorrentUtils {

    private val gson = Gson()

    actual fun getTorrentInfo(
        url: String,
        title: String,
    ): TorrentInfo {

        val response = FlutterBridge.call(
            "getTorrentInfo",
            mapOf(
                "uri" to url,
            ),
        )

        val result = response.getAsJsonObject("result")

        val hash = result["hash"].asString

        val trackers = result["trackers"]
            .asJsonArray
            .map { it.asString }

        val files = result["files"]
            .asJsonArray
            .map { fileElement ->

                val file = fileElement.asJsonObject

                TorrentFile(
                    path = file["path"].asString,
                    indexFile = file["indexFile"].asInt,
                    size = file["size"].asLong,
                    torrentHash = hash,
                    trackers = trackers,
                )
            }

        return TorrentInfo(
            title = result["title"].asString,
            files = files,
            hash = hash,
            size = result["size"].asLong,
            trackers = trackers,
        )
    }
}