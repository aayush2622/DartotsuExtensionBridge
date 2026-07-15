package com.aayush262.dartotsu_extension_bridge

import android.app.Application
import android.os.Looper
import com.aayush262.dartotsu_extension_bridge.ireader.prefs.PreferenceStoreFactory
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import ireader.core.http.HttpClients
import ireader.core.prefs.PreferenceStore
import com.aayush262.dartotsu_extension_bridge.ireader.prefs.PrefixedPreferenceStore
import org.koin.core.context.GlobalContext
import org.koin.core.context.startKoin
import org.koin.dsl.module
import org.koin.mp.KoinPlatformTools
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import xyz.nulldev.androidcompat.androidimpl.CustomContext
import xyz.nulldev.androidcompat.xyz.nulldev.androidcompat.androidCompatModule
import java.io.File
actual object PlatformInit {
    actual fun initializeAndroid(context: Any) {}

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


        val preferences = PreferenceStoreFactory().create("catalogs_data", rootPath = basePath)
        val httpClients = HttpClients(
            PrefixedPreferenceStore(
                preferences, "global"
            )
        )
        startKoin {
            modules(
                module {
                    single<Application> { application }
                    single<PreferenceStore> { preferences }
                    single<HttpClients> { httpClients }
                },
                androidCompatModule(root),
            )
        }
        val app: CustomContext by KoinPlatformTools.defaultContext().get().inject()
        application.attach(app)
        application.onCreate()
    }
}
