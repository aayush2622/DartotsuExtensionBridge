package com.aayush262.dartotsu_extension_bridge

import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import com.google.gson.Gson
import com.google.gson.JsonObject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
object Server {
    private val outputLock = Any()
    private val requestScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Serializes concurrent RPCs that target the same source.
     *
     * Many Mihon/Aniyomi sources keep pagination cursors and other mutable
     * state on the source object, so overlapping calls to one source corrupt
     * each other. M-Extension-Server guards this with a per-instance lock in
     * `ExtensionInstanceCache`; the sidecar (`run`) fans every line out on
     * `requestScope`, and the embedded bridge can be driven from several native
     * threads, so both need the same guard. Calls to *different* sources still
     * run in parallel.
     */
    private val sourceLocks = java.util.concurrent.ConcurrentHashMap<String, Mutex>()

    private suspend fun <T> withSourceLock(params: JsonObject, block: suspend () -> T): T {
        val id = params["sourceId"]?.asString ?: return block()
        return sourceLocks.getOrPut(id) { Mutex() }.withLock { block() }
    }

    /**
     * One request in, envelope JSON out — the entry point the iOS
     * [EmbeddedBridge] reflects into (`Main.handle`). Runs entirely inside the
     * backend JAR's own class loader, so `runBlocking` / [Gson] / [handle] are
     * all the backend's own copies (see [EmbeddedBridge] isolation notes).
     */
    @JvmStatic
    fun handleEmbedded(api: ExtensionApi, requestJson: String): String {
        val gson = Gson()
        return try {
            val req = gson.fromJson(requestJson, JsonObject::class.java)
            val method = req["method"].asString
            val params = req["args"]?.asJsonObject ?: JsonObject()
            val data = runBlocking { withSourceLock(params) { handle(api, method, params) } }
            gson.toJson(mapOf("success" to true, "data" to data))
        } catch (e: Throwable) {
            gson.toJson(
                mapOf(
                    "success" to false,
                    "error" to (e.message ?: e.javaClass.simpleName),
                    "trace" to e.stackTraceToString(),
                ),
            )
        }
    }

    /**
     * Runs one request against [api] and returns its payload (already a JSON
     * string, or a JSON-encoded scalar). Shared by the desktop stdio loop
     * ([run]) and the iOS in-process bridge ([EmbeddedBridge]).
     */
    suspend fun handle(
        api: ExtensionApi,
        method: String,
        params: JsonObject,
    ): String = when (method) {
        "initializeDesktop" -> {
            api.initializeDesktop(params["path"].asString)
            """{"success":true}"""
        }

        "initClient" -> {
            if (api is ExtensionBridgeApi) {
                api.initClient(params["data"].asString)
            }
            """{"success":true}"""
        }

        "getInstalledAnimeExtensions" ->
            api.getInstalledAnimeExtensions(params["path"].asString)

        "getInstalledMangaExtensions" ->
            api.getInstalledMangaExtensions(params["path"].asString)

        "getInstalledNovelExtensions" ->
            api.getInstalledNovelExtensions(params["path"].asString)

        "getPopular" -> api.getPopular(
            params["sourceId"].asString,
            params["isAnime"].asBoolean,
            params["page"].asInt,
        )

        "getLatestUpdates" -> api.getLatestUpdates(
            params["sourceId"].asString,
            params["isAnime"].asBoolean,
            params["page"].asInt,
        )

        "search" -> api.search(
            params["sourceId"].asString,
            params["isAnime"].asBoolean,
            params["query"].asString,
            params["page"].asInt,
        )

        "getDetail" -> api.getDetail(
            params["sourceId"].asString,
            params["isAnime"].asBoolean,
            params["media"].asString,
        )

        "getVideoList" -> api.getVideoList(
            params["sourceId"].asString,
            params["isAnime"].asBoolean,
            params["episode"].asString,
        )

        "getPageList" -> api.getPageList(
            params["sourceId"].asString,
            params["isAnime"].asBoolean,
            params["episode"].asString,
        )

        "getNovelContent" -> api.getNovelContent(
            params["sourceId"].asString,
            params["episode"].asString,
        )

        "getPreference" -> api.getPreference(
            params["sourceId"].asString,
            params["isAnime"].asBoolean,
        )

        "saveSourcePreference" -> api.saveSourcePreference(
            params["sourceId"].asString,
            params["key"].asString,
            params["value"].asString,
        ).toString()

        "ping" -> "\"pong\""

        else -> throw IllegalArgumentException("Unknown method: $method")
    }

    fun run(api: ExtensionApi) {

        val gson = Gson()

        val reader = System.`in`.bufferedReader()

        while (true) {
            val line = reader.readLine() ?: break
            if (line.isBlank()) continue

            requestScope.launch {
                var id: Int? = null
                try {
                    val req = gson.fromJson(
                        line,
                        JsonObject::class.java,
                    )

                    id = req["id"]?.asInt

                    val method = req["method"].asString
                    val params = req["args"]?.asJsonObject ?: JsonObject()

                    val result = withSourceLock(params) { handle(api, method, params) }

                    synchronized(outputLock) {
                        println(
                            gson.toJson(
                                mapOf(
                                    "id" to id,
                                    "success" to true,
                                    "data" to result,
                                ),
                            ),
                        )
                        System.out.flush()

                    }
                } catch (e: Exception) {
                    synchronized(outputLock) {
                        println(
                            gson.toJson(
                                mapOf(
                                    "id" to id,
                                    "success" to false,
                                    "error" to (e.message ?: "unknown"),
                                    "trace" to e.stackTraceToString(),
                                ),
                            ),
                        )
                        System.out.flush()
                    }

                }
            }
        }
    }
}
