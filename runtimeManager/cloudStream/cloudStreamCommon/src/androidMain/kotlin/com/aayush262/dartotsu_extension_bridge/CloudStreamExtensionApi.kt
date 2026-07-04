package com.aayush262.dartotsu_extension_bridge

import android.content.Context
import com.lagradost.cloudstream3.AcraApplication
import com.lagradost.cloudstream3.CloudStreamApp
import com.lagradost.cloudstream3.utils.DataStore


actual object PlatformInit {
    actual fun initializeAndroid(context: Any) {
        DataStore.init(context as Context)
        AcraApplication.context = context
        CloudStreamApp.context = context
    }

    actual fun initializeDesktop(basePath: String) {
    }
}