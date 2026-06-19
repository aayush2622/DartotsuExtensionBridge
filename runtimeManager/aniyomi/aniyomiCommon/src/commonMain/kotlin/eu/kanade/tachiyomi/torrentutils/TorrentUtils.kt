package eu.kanade.tachiyomi.torrentutils

import eu.kanade.tachiyomi.torrentutils.model.TorrentInfo

expect object TorrentUtils {
    fun getTorrentInfo(
        url: String,
        title: String,
    ): TorrentInfo
}