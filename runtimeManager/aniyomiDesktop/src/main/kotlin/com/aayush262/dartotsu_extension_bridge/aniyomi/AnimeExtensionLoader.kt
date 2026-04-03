package com.aayush262.dartotsu_extension_bridge.aniyomi

import com.aayush262.dartotsu_extension_bridge.aniyomi.util.PackageTools
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.AnimeSource
import eu.kanade.tachiyomi.animesource.AnimeSourceFactory
import eu.kanade.tachiyomi.extension.anime.model.AnimeExtension
import java.io.File
import kotlin.collections.map
import kotlin.io.extension

object AnimeExtensionLoader {

    private const val EXTENSION_FEATURE = "tachiyomi.animeextension"
    private const val METADATA_SOURCE_CLASS = "tachiyomi.animeextension.class"
    private const val METADATA_SOURCE_FACTORY = "tachiyomi.animeextension.factory"
    private const val METADATA_NSFW = "tachiyomi.animeextension.nsfw"
    private const val METADATA_HAS_README = "tachiyomi.animeextension.hasReadme"
    private const val METADATA_HAS_CHANGELOG = "tachiyomi.animeextension.hasChangelog"

    const val LIB_VERSION_MIN = 12.0
    const val LIB_VERSION_MAX = 16.0

    fun loadExtensions(path: String): List<AnimeExtension.Installed> {
        val dir = File(path)

        if (!dir.exists() || !dir.isDirectory) return emptyList()

        val apks = dir.listFiles()
            ?.filter { it.isFile && it.extension == "apk" }
            ?: emptyList()

        val byPackage = mutableMapOf<String, AnimeExtension.Installed>()

        apks.forEach { apk ->
            try {
                val ext = loadExtensionInternal(apk)

                val existing = byPackage[ext.pkgName]
                if (existing == null || ext.versionCode > existing.versionCode) {
                    byPackage[ext.pkgName] = ext
                }

            } catch (e: Throwable) {
                println("Failed to load ${apk.name}: ${e.message}\n${e.stackTraceToString()}")
            }
        }

        println("Loaded ${byPackage.size} anime extensions")

        return byPackage.values.toList()
    }

    private fun loadExtensionInternal(apkFile: File): AnimeExtension.Installed {
        val apkPath = apkFile.absolutePath
        val apkInfo = PackageTools.getPackageInfo(apkPath)
        val packageInfo = apkInfo.packageInfo
        val apkParser = apkInfo.apkFile

        require(packageInfo.reqFeatures.orEmpty().any { it.name == EXTENSION_FEATURE }) {
            "Not an anime extension: ${apkFile.name}"
        }

        val iconDir = File(apkFile.parentFile, "icons")

        val iconFile = PackageTools.extractIcon(
            apkParser,
            apkFile,
            iconDir,
            packageInfo.packageName
        )

        val iconPath = iconFile?.absolutePath

        val versionName = packageInfo.versionName!!
        val versionCode = packageInfo.versionCode.toLong()

        val libVersion = versionName.substringBeforeLast('.').toDouble()

        require(libVersion in LIB_VERSION_MIN..LIB_VERSION_MAX) {
            "Unsupported lib version: $libVersion"
        }

        val meta = packageInfo.applicationInfo.metaData

        val isNsfw = meta.getString(METADATA_NSFW) == "1"
        val hasReadme = meta.getString(METADATA_HAS_README) == "1"
        val hasChangelog = meta.getString(METADATA_HAS_CHANGELOG) == "1"

        val baseClass = meta.getString(METADATA_SOURCE_CLASS)
            ?: error("Missing source class")

        val classNames = baseClass.split(";").map {
            if (it.startsWith(".")) packageInfo.packageName + it else it
        }

        val jarDir = File(apkFile.parentFile, "jar")
        if (!jarDir.exists()) jarDir.mkdirs()

        val jarFile = File(jarDir, "${packageInfo.packageName}.jar")

        val shouldBuildJar = when {
            !jarFile.exists() -> true
            apkFile.lastModified() > jarFile.lastModified() -> true
            else -> false
        }

        if (shouldBuildJar) {
            try {
                PackageTools.dex2jar(apkPath, jarFile.absolutePath)
                PackageTools.extractAssetsFromApk(apkPath, jarFile.absolutePath)
            } catch (e: Exception) {
                println("Failed to build jar for ${apkFile.name}: ${e.message}")
                throw e
            }
        }

        val sources = mutableListOf<AnimeSource>()

        classNames.forEach { className ->
            val result = when (
                val instance = PackageTools.loadExtensionSources(
                    jarFile.absolutePath,
                    className
                )
            ) {
                is AnimeSource -> listOf(instance)
                is AnimeSourceFactory -> instance.createSources()
                else -> error("Unknown source type: ${instance.javaClass}")
            }

            sources += result
        }

        val catalogueSources = sources.filterIsInstance<AnimeCatalogueSource>()
        val langs = catalogueSources.map { it.lang }.toSet()

        val lang = when (langs.size) {
            0 -> ""
            1 -> langs.first()
            else -> "all"
        }

        val name =
            packageInfo.applicationInfo.nonLocalizedLabel
                ?.toString()
                ?.substringAfter("Aniyomi: ")
                ?: packageInfo.packageName

        apkParser.close()

        return AnimeExtension.Installed(
            name = name,
            pkgName = packageInfo.packageName,
            versionName = versionName,
            versionCode = versionCode,
            libVersion = libVersion,
            lang = lang,
            isNsfw = isNsfw,
            hasReadme = hasReadme,
            hasChangelog = hasChangelog,
            sources = sources,
            iconUrl = iconPath,
            pkgFactory = meta.getString(METADATA_SOURCE_FACTORY),
            isUnofficial = true,
            isShared = false,
        )
    }
}