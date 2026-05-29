package eu.kanade.tachiyomi.torrentutils

import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.torrentutils.model.TorrentFile
import eu.kanade.tachiyomi.torrentutils.model.TorrentInfo
import okhttp3.Request
import uy.kohesive.injekt.injectLazy
import java.security.MessageDigest
import com.dampcake.bencode.Bencode
import com.dampcake.bencode.Type
import java.nio.charset.StandardCharsets

object TorrentUtils {

    private val network: NetworkHelper by injectLazy()

    fun getTorrentInfo(
        url: String,
        title: String,
    ): TorrentInfo {
        val response = network.client.newCall(
            Request.Builder()
                .url(url)
                .build(),
        ).execute()

        val bytes = response.body.bytes()

        val decoder = Bencode(StandardCharsets.UTF_8)
        val torrent = decoder.decode(bytes, Type.DICTIONARY)

        @Suppress("UNCHECKED_CAST")
        val info = torrent["info"] as Map<String, Any>

        val trackers = buildList {
            (torrent["announce"] as? String)?.let(::add)

            (torrent["announce-list"] as? List<*>)?.forEach { tier ->
                (tier as? List<*>)?.forEach {
                    (it as? String)?.let(::add)
                }
            }
        }.distinct()

        val hash = sha1BencodedInfo(info)

        val files = mutableListOf<TorrentFile>()
        var totalSize = 0L

        val multiFiles = info["files"] as? List<*>

        if (multiFiles != null) {
            multiFiles.forEachIndexed { index, fileObj ->
                val file = fileObj as Map<String, Any>

                val length = (file["length"] as Number).toLong()

                val path = (file["path"] as List<*>)
                    .joinToString("/") { it.toString() }

                totalSize += length

                files += TorrentFile(
                    path = path,
                    indexFile = index,
                    size = length,
                    torrentHash = hash,
                    trackers = trackers,
                )
            }
        } else {
            val name = info["name"]?.toString() ?: title
            val length = (info["length"] as Number).toLong()

            totalSize = length

            files += TorrentFile(
                path = name,
                indexFile = 0,
                size = length,
                torrentHash = hash,
                trackers = trackers,
            )
        }

        return TorrentInfo(
            title = title,
            files = files,
            hash = hash,
            size = totalSize,
            trackers = trackers,
        )
    }

    private fun sha1BencodedInfo(info: Map<String, Any>): String {
        val encoder = Bencode(StandardCharsets.UTF_8)
        val encodedInfo = encoder.encode(info)

        return MessageDigest
            .getInstance("SHA-1")
            .digest(encodedInfo)
            .joinToString("") { "%02x".format(it) }
    }
}