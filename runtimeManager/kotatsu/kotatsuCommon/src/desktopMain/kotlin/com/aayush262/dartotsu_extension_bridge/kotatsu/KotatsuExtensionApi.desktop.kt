package com.aayush262.dartotsu_extension_bridge.kotatsu
import android.app.Application
import android.content.Context
import android.os.Looper
import com.aayush262.dartotsu_extension_bridge.CommonDesktopApi
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import kotlinx.serialization.json.Json
import org.koin.core.context.GlobalContext
import org.koin.core.context.startKoin
import org.koin.dsl.module
import org.koin.mp.KoinPlatformTools
import xyz.nulldev.androidcompat.androidimpl.CustomContext
import xyz.nulldev.androidcompat.xyz.nulldev.androidcompat.androidCompatModule
import java.io.File
import kotlin.getValue

actual object PlatformInit {
    actual fun initializeAndroid(context: Any) {
    }

    actual fun initializeDesktop(basePath: String) {

        val root = File(basePath).apply { mkdirs() }
        CommonDesktopApi.init(root.absolutePath)
        if (GlobalContext.getOrNull() != null) {
            Logger.log("Koin already started")
            return
        }
        val context = object : Application() {}
        val mainLoop = object : Thread() {
            override fun run() {
                Looper.prepareMainLooper()
                Looper.loop()
            }
        }
        mainLoop.start()
        startKoin {
            modules(
                listOf(
                    module {
                        single<Application> { context }
                        single<Context> { context }
                        single { Json { ignoreUnknownKeys = true } }

                    },
                    androidCompatModule(root),
                )
            )
        }
        val app: CustomContext by KoinPlatformTools.defaultContext().get().inject()
        context.attach(app)
        context.onCreate()
    }
}