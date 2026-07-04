package com.aayush262.dartotsu_extension_bridge

import android.app.Application
import android.os.Looper
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.lagradost.cloudstream3.AcraApplication
import com.lagradost.cloudstream3.CloudStreamApp
import com.lagradost.cloudstream3.utils.DataStore
import org.koin.core.context.GlobalContext
import org.koin.core.context.startKoin
import org.koin.dsl.module
import org.koin.mp.KoinPlatformTools
import xyz.nulldev.androidcompat.androidimpl.CustomContext
import xyz.nulldev.androidcompat.xyz.nulldev.androidcompat.androidCompatModule
import java.io.File

actual object PlatformInit {
    actual fun initializeAndroid(context: Any) {
    }

    actual fun initializeDesktop(basePath: String) {
        val root = File(basePath).also(File::mkdirs)
        CommonDesktopApi.init(root.absolutePath)

        if (GlobalContext.getOrNull() != null) {
            Logger.log("Koin already started")
            return
        }

        val application = object : Application() {}

        Thread {
            Looper.prepareMainLooper()
            Looper.loop()
        }.apply {
            name = "AndroidMainLooper"
            isDaemon = true
            start()
        }

        startKoin {
            modules(
                module {
                    single<Application> { application }
                },
                androidCompatModule(root),
            )
        }

        val customContext: CustomContext =
            KoinPlatformTools.defaultContext().get().get()

        application.attach(customContext)
        application.onCreate()

        DataStore.init(application)
        AcraApplication.context = application
        CloudStreamApp.context = application

    }
}