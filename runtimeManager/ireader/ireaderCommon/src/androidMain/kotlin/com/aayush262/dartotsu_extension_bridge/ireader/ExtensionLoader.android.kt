package com.aayush262.dartotsu_extension_bridge.ireader

import android.app.Application
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import dalvik.system.DexClassLoader
import ireader.core.http.HttpClients
import ireader.core.prefs.PreferenceStore
import com.aayush262.dartotsu_extension_bridge.ireader.prefs.PrefixedPreferenceStore
import ireader.core.source.CatalogSource
import ireader.core.source.Dependencies
import ireader.core.source.HttpSource
import org.koin.mp.KoinPlatform.getKoin
import java.io.File
import java.lang.reflect.Modifier


actual object ExtensionLoader {

    actual val plugins = mutableMapOf<Long, CatalogSource>()

    actual fun loadExtensions(path: String): List<LoadedExtension> {
        plugins.clear()

        return File(path)
            .listFiles()
            .orEmpty()
            .filter { it.isFile && it.extension.equals("apk", true) }
            .mapNotNull { file ->
                runCatching {
                    loadExtension(file).also {
                        plugins[it.source.id] = it.source
                    }
                }.onFailure {
                    Logger.log(
                        "Failed to load ${file.name}: ${it.message}\n${it.stackTraceToString()}"
                    )
                }.getOrNull()
            }
    }


    private fun loadExtension(apk: File): LoadedExtension {

        val application: Application = getKoin().get()

        val pm = application.packageManager

        val packageInfo = pm.getPackageArchiveInfo(
            apk.absolutePath,
            PackageManager.GET_META_DATA
        ) ?: error("Failed to parse APK")

        val appInfo = packageInfo.applicationInfo

        appInfo?.sourceDir = apk.absolutePath
        appInfo?.publicSourceDir = apk.absolutePath

        val packageName = packageInfo.packageName
        val description = appInfo?.metaData?.getString("source.description").orEmpty()
        val icon = appInfo?.metaData?.getString("source.icon").orEmpty()
        val sourceClass = appInfo?.metaData?.getString("source.class")
            ?: error("Missing source.class metadata")

        val className =
            if (sourceClass.startsWith(".")) {
                packageName + sourceClass
            } else {
                sourceClass
            }

        val prefs = PrefixedPreferenceStore(
            getKoin().get<PreferenceStore>(),
            packageName
        )

        val deps = Dependencies(
            getKoin().get<HttpClients>(),
            prefs
        )

        val optimizedDir = File(application.codeCacheDir, "ireader_dex").apply {
            mkdirs()
        }

        val loader = DexClassLoader(
            apk.absolutePath,
            optimizedDir.absolutePath,
            null,
            javaClass.classLoader
        )

        val clazz = Class.forName(
            className,
            false,
            loader
        )

        require(!Modifier.isAbstract(clazz.modifiers)) {
            "Source class is abstract: $className"
        }

        val instance = clazz
            .getDeclaredConstructor(Dependencies::class.java)
            .newInstance(deps)

        require(instance is CatalogSource) {
            "Loaded class $className is not a CatalogSource (${instance::class.java.name})"
        }

        plugins[instance.id] = instance

        return LoadedExtension(
            source = instance,
            packageName = packageName,
            versionName = packageInfo.versionName.orEmpty(),
            versionCode = packageInfo.compatVersionCode,
            apkPath = apk.absolutePath,
            baseUrl = (instance as? HttpSource)?.baseUrl.orEmpty(),
            icon = icon,
            description = description,
        )
    }
    @Suppress("DEPRECATION")
    private val PackageInfo.compatVersionCode: Long
        get() = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            longVersionCode
        } else {
            versionCode.toLong()
        }
}