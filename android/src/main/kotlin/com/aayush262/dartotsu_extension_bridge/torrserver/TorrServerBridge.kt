package com.aayush262.dartotsu_extension_bridge.torrserver

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * The TorrServer binary is baked into `jniLibs/<abi>/libtorrserver.so` at build
 * time (see `android/build.gradle.kts`'s `downloadTorrServerBinaries` task) since
 * a runtime-downloaded file generally can't be exec'd on modern Android (W^X /
 * SELinux `noexec` on writable app-data partitions). This just hands Dart the
 * resolved `nativeLibraryDir` so `TorrServerControllerSubprocess` can exec
 * `<nativeLibraryDir>/libtorrserver.so` directly.
 */
class TorrServerBridge(private val context: Context) : MethodCallHandler {

    private lateinit var channel: MethodChannel

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            binding.binaryMessenger, "dartotsu_extension_bridge/torrserver"
        ).apply {
            setMethodCallHandler(this@TorrServerBridge)
        }
    }

    fun detach() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getNativeLibraryDir" -> result.success(context.applicationInfo.nativeLibraryDir)
            else -> result.notImplemented()
        }
    }
}
