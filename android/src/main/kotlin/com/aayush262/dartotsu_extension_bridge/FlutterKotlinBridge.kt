package com.aayush262.dartotsu_extension_bridge

import android.util.Log
import com.aayush262.dartotsu_extension_bridge.network.FlutterNetwork.enableFlutterNetworking
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
class FlutterKotlinBridge(private val channel: MethodChannel): MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initClient" -> {
                val args = call.arguments as? Map<*, *> ?: return result.error("INVALID_ARGUMENTS", "Expected a map of arguments", null)
                enableFlutterNetworking(channel,args);
                Log.d( TAG, "Flutter networking enabled");
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}