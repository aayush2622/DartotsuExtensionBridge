package com.aayush262.dartotsu_extension_bridge

import android.content.Context
import com.aayush262.dartotsu_extension_bridge.cloudStream.AndroidPreferenceRecorder
import com.aayush262.dartotsu_extension_bridge.cloudStream.RecordingContext
import com.lagradost.cloudstream3.AcraApplication
import com.lagradost.cloudstream3.CloudStreamApp
import com.lagradost.cloudstream3.utils.DataStore


actual object PlatformInit {
    private var heldContext: RecordingContext? = null

    actual fun initializeAndroid(context: Any) {
        val app = (context as Context).applicationContext ?: context
        AndroidPreferenceRecorder.init(app)
        val recording = RecordingContext(app)
        heldContext = recording
        DataStore.init(recording)
        AcraApplication.context = recording
        CloudStreamApp.context = recording
    }

    actual fun initializeDesktop(basePath: String) {
    }
}