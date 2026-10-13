package eu.kanade.tachiyomi.animesource.model

import eu.kanade.tachiyomi.animesource.model.SerializableVideo.Companion.serialize
import eu.kanade.tachiyomi.animesource.model.SerializableVideo.Companion.toVideoList
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

open class Hoster(
    val hosterUrl: String = "",
    val hosterName: String = "",
    val videoList: List<Video>? = null,
    /**
     * Superseded by [memo] in extensions-lib 17. Still honoured so extensions built against
     * lib 16 and earlier keep working.
     */
    val internalData: String = "",
    val lazy: Boolean = false,
    /**
     * Extra metadata associated with the hoster. Not visible to users; intended for internal or
     * source-specific purposes.
     *
     * @since extensions-lib 17
     */
    val memo: JsonObject = JsonObject(emptyMap()),
) {
    /**
     * Binary-compat shim for extensions compiled against extensions-lib 16 and
     * earlier (before [memo] existed). Kotlin's default-argument calling
     * convention doesn't use plain overloads - a caller that omits trailing
     * defaulted args compiles to a call against a synthetic
     * `<init>(..., int mask, DefaultConstructorMarker)` bridge tied to the
     * exact parameter list the constructor had *at the caller's compile
     * time*. Adding [memo] changed that bridge's shape for the primary
     * constructor, so pre-lib-17 extensions calling the old 5-param bridge
     * got `NoSuchMethodError` even though `@JvmOverloads` provided a matching
     * plain overload - `@JvmOverloads` doesn't regenerate this bridge, only
     * a constructor's own defaults do. This secondary constructor exists
     * solely so Kotlin generates that exact missing bridge again.
     */
    constructor(
        hosterUrl: String = "",
        hosterName: String = "",
        videoList: List<Video>? = null,
        internalData: String = "",
        lazy: Boolean = false,
    ) : this(hosterUrl, hosterName, videoList, internalData, lazy, JsonObject(emptyMap()))

    @Transient
    @Volatile
    var status: State = State.IDLE

    enum class State {
        IDLE,
        LOADING,
        READY,
        ERROR,
    }

    fun copy(
        hosterUrl: String = this.hosterUrl,
        hosterName: String = this.hosterName,
        videoList: List<Video>? = this.videoList,
        internalData: String = this.internalData,
        lazy: Boolean = this.lazy,
        memo: JsonObject = this.memo,
    ): Hoster {
        return Hoster(hosterUrl, hosterName, videoList, internalData, lazy, memo)
    }

    companion object {
        const val NO_HOSTER_LIST = "no_hoster_list"

        fun List<Video>.toHosterList(): List<Hoster> {
            return listOf(
                Hoster(
                    hosterUrl = "",
                    hosterName = NO_HOSTER_LIST,
                    videoList = this,
                ),
            )
        }
    }
}

@Serializable
data class SerializableHoster(
    val hosterUrl: String = "",
    val hosterName: String = "",
    val videoList: String? = null,
    val internalData: String = "",
    val lazy: Boolean = false,
) {
    companion object {
        fun List<Hoster>.serialize(): String =
            Json.encodeToString(
                this.map { host ->
                    SerializableHoster(
                        host.hosterUrl,
                        host.hosterName,
                        host.videoList?.serialize(),
                        host.internalData,
                        host.lazy,
                    )
                },
            )

        fun String.toHosterList(): List<Hoster> =
            Json.decodeFromString<List<SerializableHoster>>(this)
                .map { sHost ->
                    Hoster(
                        sHost.hosterUrl,
                        sHost.hosterName,
                        sHost.videoList?.toVideoList(),
                        sHost.internalData,
                        sHost.lazy,
                    )
                }
    }
}
