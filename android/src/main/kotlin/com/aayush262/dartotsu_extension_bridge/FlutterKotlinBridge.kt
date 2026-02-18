package com.aayush262.dartotsu_extension_bridge

import android.util.Log
import com.aayush262.dartotsu_extension_bridge.network.FlutterNetwork.enableFlutterNetworking
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
class FlutterKotlinBridge {

    private lateinit var channel: MethodChannel

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        Logger.init(channel)
        channel = MethodChannel(
            binding.binaryMessenger,
            "flutterKotlinBridge"
        ).apply {
            setMethodCallHandler(Handler())
        }
    }

    fun detach() = channel.setMethodCallHandler(null)


    private inner class Handler : MethodChannel.MethodCallHandler {
        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "initClient" -> {
                    val args = call.arguments as? Map<*, *>
                        ?: return result.error(
                            "INVALID_ARGUMENTS",
                            "Expected a map",
                            null
                        )

                    enableFlutterNetworking(channel, args)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}