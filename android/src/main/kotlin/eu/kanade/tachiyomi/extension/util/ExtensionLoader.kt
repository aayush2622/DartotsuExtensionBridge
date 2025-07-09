package eu.kanade.tachiyomi.extension.util

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import dalvik.system.PathClassLoader
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.AnimeSource
import eu.kanade.tachiyomi.animesource.AnimeSourceFactory
import eu.kanade.tachiyomi.extension.anime.model.AnimeExtension
import eu.kanade.tachiyomi.extension.anime.model.AnimeLoadResult
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import java.io.File
import java.io.FileOutputStream

/**
 * Class that handles the loading of the extensions. Supports two kinds of extensions:
 *
 * 1. Shared extension: This extension is installed to the system with package
 * installer, so other variants of Tachiyomi and its forks can also use this extension.
 *
 * 2. Private extension: This extension is put inside private data directory of the
 * running app, so this extension can only be used by the running app and not shared
 * with other apps.
 *
 * When both kinds of extensions are installed with a same package name, shared
 * extension will be used unless the version codes are different. In that case the
 * one with higher version code will be used.
 */
private const val ANIME_PACKAGE = "tachiyomi.animeextension"
private const val MANGA_PACKAGE = "tachiyomi.extension"

internal object ExtensionLoader {
    private const val XX_METADATA_SOURCE_CLASS = ".class"
    private const val XX_METADATA_SOURCE_FACTORY = ".factory"
    private const val XX_METADATA_NSFW = "n.nsfw"
    private const val XX_METADATA_HAS_README = ".hasReadme"
    private const val XX_METADATA_HAS_CHANGELOG = ".hasChangelog"

    const val ANIME_LIB_VERSION_MIN = 12
    const val ANIME_LIB_VERSION_MAX = 15

    val PACKAGE_FLAGS = PackageManager.GET_CONFIGURATIONS or
            PackageManager.GET_META_DATA or
            @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                PackageManager.GET_SIGNING_CERTIFICATES else 0)


    fun loadAnimeExtensions(context: Context): List<AnimeLoadResult> {
        val pkgManager = context.packageManager


        val installedPackages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pkgManager.getInstalledPackages(PackageManager.PackageInfoFlags.of(PACKAGE_FLAGS.toLong()))
        } else {
            pkgManager.getInstalledPackages(PACKAGE_FLAGS)
        }
        val extPkgs = installedPackages.filter { isPackageAnExtension(MediaType.ANIME, it) }

        if (extPkgs.isEmpty()) return emptyList()

        return runBlocking {
            val deferred = extPkgs.map {
                async { loadAnimeExtension(context, it.packageName, it) }
            }
            deferred.map { it.await() }
        }
    }
    private fun isPackageAnExtension(type: MediaType, pkgInfo: PackageInfo): Boolean {

        return if (type == MediaType.NOVEL) {
            pkgInfo.packageName.startsWith("some.random")
        } else {
            pkgInfo.reqFeatures.orEmpty().any {
                it.name == when (type) {
                    MediaType.ANIME -> ANIME_PACKAGE
                    MediaType.MANGA -> MANGA_PACKAGE
                    else -> ""
                }
            }
        }
    }
    private fun loadAnimeExtension(
        context: Context,
        pkgName: String,
        pkgInfo: PackageInfo
    ): AnimeLoadResult {
        val pkgManager = context.packageManager

        val appInfo = try {
            pkgManager.getApplicationInfo(pkgName, PackageManager.GET_META_DATA)
        } catch (error: PackageManager.NameNotFoundException) {
            // Unlikely, but the package may have been uninstalled at this point
            println(error)
            return AnimeLoadResult.Error
        }

        val extName = pkgManager.getApplicationLabel(appInfo).toString().substringAfter("Aniyomi: ")
        val versionName = pkgInfo.versionName
        
        /*val versionCode = PackageInfoCompat.getLongVersionCode(pkgInfo)*/

        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            pkgInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            pkgInfo.versionCode.toLong()
        }

        if (versionName.isNullOrEmpty()) {
            println("Missing versionName for extension $extName")
            return AnimeLoadResult.Error
        }

        // Validate lib version
        val libVersion = versionName.substringBeforeLast('.').toDoubleOrNull()
        if (libVersion == null || libVersion < ANIME_LIB_VERSION_MIN || libVersion > ANIME_LIB_VERSION_MAX) {
            println(
                "Lib version is $libVersion, while only versions " +
                        "$ANIME_LIB_VERSION_MIN to $ANIME_LIB_VERSION_MAX are allowed"
            )
            return AnimeLoadResult.Error
        }

        val isNsfw = appInfo.metaData.getInt("${ANIME_PACKAGE}${XX_METADATA_NSFW}") == 1


        val hasReadme = appInfo.metaData.getInt("${ANIME_PACKAGE}${XX_METADATA_HAS_README}", 0) == 1
        val hasChangelog =
            appInfo.metaData.getInt("${ANIME_PACKAGE}${XX_METADATA_HAS_CHANGELOG}", 0) == 1

        val classLoader = try{
            PathClassLoader(appInfo.sourceDir, null, context.classLoader)
        } catch (e: Throwable) {
            println("Error creating class loader for $pkgName: ${e.message}")
            return AnimeLoadResult.Error
        }
        val sources = appInfo.metaData.getString("$ANIME_PACKAGE$XX_METADATA_SOURCE_CLASS")!!
            .split(";")
            .map {
                val sourceClass = it.trim()
                if (sourceClass.startsWith(".")) {
                    pkgInfo.packageName + sourceClass
                } else {
                    sourceClass
                }
            }
            .flatMap {
                try {
                    when (val obj = Class.forName(it, false, classLoader).getDeclaredConstructor()
                        .newInstance()) {
                        is AnimeSource -> listOf(obj)
                        is AnimeSourceFactory -> obj.createSources()
                        else -> throw Exception("Unknown source class type! ${obj.javaClass}")
                    }
                } catch (e : Throwable) {
                    println("Error loading $it: ${e.message}")
                    return AnimeLoadResult.Error
                }
            }

        val langs = sources.filterIsInstance<AnimeCatalogueSource>()
            .map { it.lang }
            .toSet()
        val lang = when (langs.size) {
            0 -> ""
            1 -> langs.first()
            else -> "all"
        }

        val extension = AnimeExtension.Installed(
            name = extName,
            pkgName = pkgName,
            versionName = versionName,
            versionCode = versionCode,
            libVersion = libVersion,
            lang = lang,
            isNsfw = isNsfw,
            hasReadme = hasReadme,
            hasChangelog = hasChangelog,
            sources = sources,
            pkgFactory = appInfo.metaData.getString("${ANIME_PACKAGE}${XX_METADATA_SOURCE_FACTORY}"),
            isUnofficial = true,
            icon = context.getApplicationIcon(pkgName),
        )
        return AnimeLoadResult.Success(extension)
    }
}

fun Context.getApplicationIcon(pkgName: String): String? {
    return try {
        val drawable = packageManager.getApplicationIcon(pkgName)
        val bitmap = (drawable as BitmapDrawable).bitmap
        val file = File(cacheDir, "icon.png")
        val output = FileOutputStream(file)
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
        output.close()
        file.absolutePath
    } catch (e: PackageManager.NameNotFoundException) {
        println("Error getting icon for $pkgName: ${e.message}")
        null
    }
}

interface Type {
    fun asText(): String
}

enum class MediaType : Type {
    ANIME,
    MANGA,
    NOVEL;

    override fun asText(): String {
        return when (this) {
            ANIME -> "Anime"
            MANGA -> "Manga"
            NOVEL -> "Novel"
        }
    }

    companion object {
        fun fromText(string: String): MediaType? {
            return when (string) {
                "Anime" -> ANIME
                "Manga" -> MANGA
                "Novel" -> NOVEL
                else -> {
                    null
                }
            }
        }
    }
}
