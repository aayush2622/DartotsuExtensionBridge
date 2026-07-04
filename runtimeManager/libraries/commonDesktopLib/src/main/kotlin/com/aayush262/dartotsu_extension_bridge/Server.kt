package com.aayush262.dartotsu_extension_bridge

import com.aayush262.dartotsu_extension_bridge.common.ExtensionBridgeApi
import com.google.gson.Gson
import com.google.gson.JsonObject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
object Server {
    private val outputLock = Any()
    private val requestScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

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

                    val result = when (method) {
                        "initializeDesktop" -> {
                            api.initializeDesktop(
                                params["path"].asString,
                            )

                            """{"success":true}"""
                        }

                        "initClient" -> {
                            if (api is  ExtensionBridgeApi) {
                                api.initClient(
                                    params["data"].asString,
                                )
                            }
                            """{"success":true}"""
                        }

                        "getInstalledAnimeExtensions" -> {
                            api.getInstalledAnimeExtensions(
                                params["path"].asString,
                            )
                        }

                        "getInstalledMangaExtensions" -> {
                            api.getInstalledMangaExtensions(
                                params["path"].asString,
                            )
                        }

                        "getInstalledNovelExtensions" -> {
                            api.getInstalledNovelExtensions(
                                params["path"].asString,
                            )
                        }
                        "getPopular" -> {
                            api.getPopular(
                                params["sourceId"].asString,
                                params["isAnime"].asBoolean,
                                params["page"].asInt,
                            )
                        }

                        "getLatestUpdates" -> {
                            api.getLatestUpdates(
                                params["sourceId"].asString,
                                params["isAnime"].asBoolean,
                                params["page"].asInt,
                            )
                        }

                        "search" -> {
                            api.search(
                                params["sourceId"].asString,
                                params["isAnime"].asBoolean,
                                params["query"].asString,
                                params["page"].asInt,
                            )
                        }

                        "getDetail" -> {
                            api.getDetail(
                                params["sourceId"].asString,
                                params["isAnime"].asBoolean,
                                params["media"].asString,
                            )
                        }

                        "getVideoList" -> {
                            api.getVideoList(
                                params["sourceId"].asString,
                                params["isAnime"].asBoolean,
                                params["episode"].asString,
                            )
                        }

                        "getPageList" -> {
                            api.getPageList(
                                params["sourceId"].asString,
                                params["isAnime"].asBoolean,
                                params["episode"].asString,
                            )
                        }

                        "getPreference" -> {
                            api.getPreference(
                                params["sourceId"].asString,
                                params["isAnime"].asBoolean,
                            )
                        }

                        "saveSourcePreference" -> {
                            api.saveSourcePreference(
                                params["sourceId"].asString,
                                params["key"].asString,
                                params["value"].asString,
                            ).toString()
                        }

                        "ping" -> {
                            "\"pong\""
                        }

                        else -> {
                            throw IllegalArgumentException(
                                "Unknown method: $method",
                            )
                        }
                    }

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
