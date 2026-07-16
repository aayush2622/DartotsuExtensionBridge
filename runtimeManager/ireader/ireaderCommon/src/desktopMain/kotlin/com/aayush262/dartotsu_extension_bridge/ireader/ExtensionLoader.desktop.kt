package com.aayush262.dartotsu_extension_bridge.ireader

import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.aayush262.dartotsu_extension_bridge.util.PackageTools
import com.fleeksoft.ksoup.Ksoup
import com.fleeksoft.ksoup.parser.Parser
import ireader.core.http.HttpClients
import ireader.core.prefs.PreferenceStore
import com.aayush262.dartotsu_extension_bridge.ireader.prefs.PrefixedPreferenceStore
import ireader.core.source.CatalogSource
import ireader.core.source.Dependencies
import ireader.core.source.HttpSource
import net.dongliu.apk.parser.ApkFile
import net.dongliu.apk.parser.ApkParsers
import org.koin.mp.KoinPlatform.getKoin
import xyz.nulldev.androidcompat.pm.toPackageInfo
import java.io.File
import java.lang.reflect.Modifier

actual object ExtensionLoader {
    private const val EXTENSION_FEATURE = "ireader.extension"
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

        val jarDir = File(apk.parentFile, "jar").apply { mkdirs() }

        val jarFile = File(jarDir, "${apk.nameWithoutExtension}.jar")

        if (!jarFile.exists() || jarFile.lastModified() < apk.lastModified()) {
            PackageTools.dex2jar(
                apk.absolutePath,
                jarFile.absolutePath
            )

            PackageTools.extractAssetsFromApk(
                apk.absolutePath,
                jarFile.absolutePath
            )
        }
        val apkPath = apk.absolutePath

        val apkInfo = PackageTools.getPackageInfo(apkPath)
        val packageInfo = apkInfo.packageInfo
        val apkParser = apkInfo.apkFile
        require(packageInfo.reqFeatures.orEmpty().any { it.name == EXTENSION_FEATURE }) {
            "Not an extension: ${apk.name}"
        }
        val metadata = Ksoup.parse(
            apkParser.manifestXml,
            Parser.xmlParser()
        )
            .select("application")
            .select("meta-data")
            .associate {
                it.attr("android:name") to it.attr("android:value")
            }

        val packageName = apkParser.apkMeta.packageName
        val sourceClass = metadata["source.class"]
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

        val loader = PackageTools.getClassLoader(
            jarFile.absolutePath
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

        return LoadedExtension(
            source = instance,
            packageName = packageName,
            versionName = apkParser.apkMeta.versionName ?: "",
            versionCode = apkParser.apkMeta.versionCode.toLong(),
            apkPath = apk.absolutePath,
            baseUrl = (instance as? HttpSource)?.baseUrl.orEmpty(),
            icon = metadata["source.icon"].orEmpty(),
            description = metadata["source.description"].orEmpty(),
            isShared = false
        )
    }
}