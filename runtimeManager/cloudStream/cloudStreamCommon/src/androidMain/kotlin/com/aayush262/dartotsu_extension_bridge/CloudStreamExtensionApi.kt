package com.aayush262.dartotsu_extension_bridge

import android.content.Context
import com.lagradost.cloudstream3.AcraApplication
import com.lagradost.cloudstream3.CloudStreamApp
import com.lagradost.cloudstream3.utils.DataStore


actual object PlatformInit {
    actual fun initializeAndroid(context: Any) {
        val app = (context as Context).applicationContext ?: context
        DataStore.init(app)
        AcraApplication.context = app
        CloudStreamApp.context = app
    }

    actual fun initializeDesktop(basePath: String) {
    }
}