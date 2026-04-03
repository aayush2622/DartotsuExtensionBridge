package xyz.nulldev.androidcompat.xyz.nulldev.androidcompat

import android.content.Context
import org.koin.core.module.Module
import org.koin.dsl.module
import xyz.nulldev.androidcompat.androidimpl.CustomContext
import xyz.nulldev.androidcompat.androidimpl.FakePackageManager
import xyz.nulldev.androidcompat.info.ApplicationInfoImpl
import xyz.nulldev.androidcompat.io.AndroidFiles
import xyz.nulldev.androidcompat.pm.PackageController
import xyz.nulldev.androidcompat.service.ServiceSupport
import java.io.File

/**
 * AndroidCompatModule (Dartotsu version - no config)
 */
fun androidCompatModule(root: File): Module =
    module {

        // 🔥 Inject our new AndroidFiles
        single { AndroidFiles(root) }

        single {
            ApplicationInfoImpl(
                packageName = "com.aayush262.dartotsu",
                debug = false
            )
        }

        single { ServiceSupport() }

        single { FakePackageManager() }

        single { PackageController() }

        single { CustomContext() }

        single<Context> { get<CustomContext>() }
    }