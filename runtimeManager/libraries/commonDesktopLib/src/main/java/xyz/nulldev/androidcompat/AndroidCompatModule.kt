package xyz.nulldev.androidcompat.xyz.nulldev.androidcompat

import android.content.Context
import android.webkit.WebView
import org.koin.core.module.Module
import org.koin.dsl.module
import xyz.nulldev.androidcompat.androidimpl.CustomContext
import xyz.nulldev.androidcompat.androidimpl.FakePackageManager
import xyz.nulldev.androidcompat.info.ApplicationInfoImpl
import xyz.nulldev.androidcompat.io.AndroidFiles
import xyz.nulldev.androidcompat.pm.PackageController
import xyz.nulldev.androidcompat.service.ServiceSupport
import xyz.nulldev.androidcompat.webkit.KcefWebViewProvider
import java.io.File

/**
 * AndroidCompatModule (Dartotsu version - no config)
 */
fun androidCompatModule(root: File): Module =
    module {

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
    }.apply {
        init()
    }

fun init() {
    WebView.setProviderFactory { view: WebView -> KcefWebViewProvider(view) }

    System.setProperty(
        "http.agent",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
    )
}
