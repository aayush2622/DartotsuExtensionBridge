package com.aayush262.dartotsu_extension_bridge

import android.app.Application
import android.content.Context
import com.aayush262.dartotsu_extension_bridge.ireader.prefs.PreferenceStoreFactory
import com.aayush262.dartotsu_extension_bridge.ireader.prefs.PrefixedPreferenceStore
import ireader.core.http.AcceptAllCookiesStorage
import ireader.core.http.BrowserEngine
import ireader.core.http.CookieSynchronizer
import ireader.core.http.HttpClients
import ireader.core.http.WebViewCookieJar
import ireader.core.http.WebViewManger
import ireader.core.prefs.PreferenceStore
import org.koin.core.context.startKoin
import org.koin.dsl.module
import xyz.nulldev.androidcompat.xyz.nulldev.androidcompat.androidCompatModule

actual object PlatformInit {
    actual fun initializeAndroid(context: Any) {
        val ctx = context as? Context ?: return
        val preferences = PreferenceStoreFactory(ctx).create("catalogs_data", rootPath = "")

        val cookiesStorage = AcceptAllCookiesStorage()
        val webViewCookieJar = WebViewCookieJar(cookiesStorage)
        val webViewManager = WebViewManger(ctx)
        val browserEngine = BrowserEngine(
            webViewManager,
            webViewCookieJar,
        )

        val httpClients = HttpClients(
            context = ctx,
            browseEngine = browserEngine,
            cookiesStorage = cookiesStorage,
            webViewCookieJar = webViewCookieJar,
            preferencesStore = preferences,
            webViewManager = webViewManager,
        )
        startKoin {
            modules(
                module {
                    single<Application> { ctx as Application }
                    single<PreferenceStore> { preferences }
                    single<HttpClients> { httpClients }
                },
            )
        }
    }

    actual fun initializeDesktop(basePath: String) {}
}
