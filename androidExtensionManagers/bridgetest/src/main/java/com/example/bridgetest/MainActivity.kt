package com.example.bridgetest

import android.app.Application
import android.content.Context
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.aayush262.dartotsu_extension_bridge.ExtensionApi
import dalvik.system.DexClassLoader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingletonFactory

class MainActivity : ComponentActivity() {

    private var api: ExtensionApi? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val application = application as Application
        Injekt.addSingletonFactory<Application> { application }

        setContent {

            var extensions by remember {
                mutableStateOf<List<Map<String, Any?>>>(emptyList())
            }

            var selected by remember {
                mutableStateOf<Map<String, Any?>?>(null)
            }

            if (selected == null) {

                ExtensionListScreen(
                    extensions = extensions,
                    onLoadExtensions = {
                        loadApi(this)
                        api?.initialize()

                        val res =
                            api?.getInstalledAnimeExtensions(null)
                                ?: emptyList()

                        extensions = res
                    },
                    onOpen = {
                        selected = it
                    }
                )

            } else {

                ExtensionMethodScreen(
                    extension = selected!!,
                    api = api,
                    onBack = { selected = null }
                )

            }
        }
    }

    private fun loadApi(context: Context) {

        if (api != null) return

        try {

            val pluginPackage =
                "com.aayush262.dartotsu.aniyomi_plugin"

            val appInfo =
                context.packageManager.getApplicationInfo(
                    pluginPackage,
                    0
                )

            val apkPath = appInfo.sourceDir

            val classLoader = DexClassLoader(
                apkPath,
                context.codeCacheDir.absolutePath,
                null,
                context.classLoader
            )

            val clazz = classLoader.loadClass(
                "com.aayush262.dartotsu_extension_bridge.AniyomiExtensionApi"
            )

            val instance =
                clazz.getDeclaredConstructor().newInstance()

            api = instance as ExtensionApi

        } catch (e: Throwable) {

            Log.e("BRIDGE", e.stackTraceToString())

        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExtensionListScreen(
    extensions: List<Map<String, Any?>>,
    onLoadExtensions: suspend () -> Unit,
    onOpen: (Map<String, Any?>) -> Unit
) {

    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(title = { Text("Extension Loader") })
        }
    ) { padding ->

        Column(
            modifier =
                Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(16.dp)
        ) {

            Button(
                modifier = Modifier.fillMaxWidth(),
                onClick = {

                    scope.launch {

                        onLoadExtensions()

                    }

                }
            ) {

                Text("Load Extensions")

            }

            Spacer(Modifier.height(16.dp))

            LazyColumn {

                items(extensions) { ext ->

                    val name =
                        ext["name"]?.toString() ?: "Unknown"

                    val icon =
                        ext["iconUrl"]?.toString()

                    val lang =
                        ext["lang"]?.toString()

                    Row(
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .clickable { onOpen(ext) }
                                .padding(12.dp)
                    ) {


                        Spacer(Modifier.width(12.dp))

                        Column {

                            Text(name)

                            Text(
                                lang ?: "",
                                style =
                                    MaterialTheme
                                        .typography
                                        .bodySmall
                            )
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExtensionMethodScreen(
    extension: Map<String, Any?>,
    api: ExtensionApi?,
    onBack: () -> Unit
) {

    val scope = rememberCoroutineScope()

    var result by remember { mutableStateOf("No data") }

    var mediaList by remember { mutableStateOf<List<Map<String, Any?>>>(emptyList()) }
    var selectedMedia by remember { mutableStateOf<Map<String, Any?>?>(null) }
    var episodes by remember { mutableStateOf<List<Map<String, Any?>>>(emptyList()) }
    var videos by remember { mutableStateOf<List<Map<String, Any?>>>(emptyList()) }

    val sourceId = extension["id"].toString()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(extension["name"].toString()) },
                navigationIcon = {
                    Text(
                        "< Back",
                        modifier = Modifier
                            .padding(16.dp)
                            .clickable { onBack() }
                    )
                }
            )
        }
    ) { padding ->

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp)
        ) {

            Button(
                modifier = Modifier.fillMaxWidth(),
                onClick = {

                    scope.launch(Dispatchers.IO) {

                        val res = api?.getPopular(sourceId, true, 1)

                        withContext(Dispatchers.Main) {

                            val map = res as Map<String, Any?>

                            mediaList = map["list"] as List<Map<String, Any?>>

                            episodes = emptyList()
                            videos = emptyList()

                            result = "Popular: ${mediaList.size} items"
                        }
                    }
                }
            ) { Text("Popular") }

            Spacer(Modifier.height(8.dp))

            Button(
                modifier = Modifier.fillMaxWidth(),
                onClick = {

                    scope.launch(Dispatchers.IO) {

                        val res = api?.getLatestUpdates(sourceId, true, 1)

                        withContext(Dispatchers.Main) {

                            val map = res as Map<String, Any?>

                            mediaList = map["list"] as List<Map<String, Any?>>

                            episodes = emptyList()
                            videos = emptyList()

                            result = "Latest: ${mediaList.size} items"
                        }
                    }
                }
            ) { Text("Latest") }

            Spacer(Modifier.height(8.dp))

            Button(
                modifier = Modifier.fillMaxWidth(),
                onClick = {

                    scope.launch(Dispatchers.IO) {

                        val res = api?.search(sourceId, true, "naruto", 1)

                        withContext(Dispatchers.Main) {

                            val map = res as Map<String, Any?>

                            mediaList = map["list"] as List<Map<String, Any?>>

                            episodes = emptyList()
                            videos = emptyList()

                            result = "Search: ${mediaList.size} items"
                        }
                    }
                }
            ) { Text("Search Naruto") }

            Spacer(Modifier.height(16.dp))

            Text("Result: $result")

            Spacer(Modifier.height(16.dp))

            LazyColumn {

                items(mediaList) { media ->

                    Text(
                        text = media["title"].toString(),
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {

                                scope.launch(Dispatchers.IO) {

                                    val detail = api?.getDetail(
                                        sourceId,
                                        true,
                                        media
                                    )

                                    withContext(Dispatchers.Main) {

                                        selectedMedia = detail

                                        episodes =
                                            detail?.get("episodes") as? List<Map<String, Any?>>
                                                ?: emptyList()

                                        videos = emptyList()
                                    }
                                }
                            }
                            .padding(8.dp)
                    )
                }

                if (episodes.isNotEmpty()) {

                    item {

                        Spacer(Modifier.height(16.dp))
                        Text("Episodes")

                    }

                    items(episodes) { ep ->

                        Text(
                            text = ep["name"].toString(),
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {

                                    scope.launch(Dispatchers.IO) {

                                        val res = api?.getVideoList(
                                            sourceId,
                                            true,
                                            ep
                                        )

                                        withContext(Dispatchers.Main) {

                                            videos = res ?: emptyList()

                                        }
                                    }
                                }
                                .padding(8.dp)
                        )
                    }
                }

                if (videos.isNotEmpty()) {

                    item {

                        Spacer(Modifier.height(16.dp))
                        Text("Videos")

                    }

                    items(videos) { video ->

                        Text(
                            text = "${video["quality"]} - ${video["title"]}",
                            modifier = Modifier.padding(8.dp)
                        )
                    }
                }
            }
        }
    }
}