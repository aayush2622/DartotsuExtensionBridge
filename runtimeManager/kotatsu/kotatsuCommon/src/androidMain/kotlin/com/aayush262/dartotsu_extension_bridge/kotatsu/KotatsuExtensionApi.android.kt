package com.aayush262.dartotsu_extension_bridge.kotatsu

import android.app.Application
import android.content.Context
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingletonFactory

actual object PlatformInit {
    actual fun initializeAndroid(context: Any) {
        val ctx = context as Context
        Injekt.addSingletonFactory<Application> { ctx as Application }
        Injekt.addSingletonFactory<Context> { ctx }

    }

    actual fun initializeDesktop(basePath: String) {
    }
}