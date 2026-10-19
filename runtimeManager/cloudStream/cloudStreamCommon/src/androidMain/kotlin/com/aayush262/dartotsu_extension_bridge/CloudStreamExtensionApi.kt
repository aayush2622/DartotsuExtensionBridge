package com.aayush262.dartotsu_extension_bridge

import android.content.Context
import com.aayush262.dartotsu_extension_bridge.cloudStream.AndroidPreferenceRecorder
import com.aayush262.dartotsu_extension_bridge.cloudStream.RecordingContext
import com.lagradost.cloudstream3.AcraApplication
import com.lagradost.cloudstream3.CloudStreamApp
import com.lagradost.cloudstream3.utils.DataStore

actual object PlatformInit {
    actual fun initializeAndroid(context: Any) {
        val app = (context as Context).applicationContext ?: context
        val recording = RecordingContext(app)
        AcraApplication.context = recording
        CloudStreamApp.context = recording
        DataStore.init(recording)
        AndroidPreferenceRecorder.init(app)
    }

    actual fun initializeDesktop(basePath: String) {
    }
}
