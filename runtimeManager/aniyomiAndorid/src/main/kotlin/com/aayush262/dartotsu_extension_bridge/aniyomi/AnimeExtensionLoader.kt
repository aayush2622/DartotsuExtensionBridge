package com.aayush262.dartotsu_extension_bridge.aniyomi

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import androidx.core.content.pm.PackageInfoCompat
import androidx.core.graphics.createBitmap
import com.aayush262.dartotsu_extension_bridge.LogLevel
import com.aayush262.dartotsu_extension_bridge.Logger
import dalvik.system.PathClassLoader
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.AnimeSource
import eu.kanade.tachiyomi.animesource.AnimeSourceFactory
import eu.kanade.tachiyomi.extension.anime.model.AnimeExtension
import eu.kanade.tachiyomi.extension.anime.model.AnimeLoadResult
import eu.kanade.tachiyomi.util.system.ChildFirstPathClassLoader
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import kotlin.collections.map
import kotlin.io.extension
import kotlin.sequences.map

internal object AnimeExtensionLoader {

    private const val EXTENSION_FEATURE = "tachiyomi.animeextension"
    private const val METADATA_SOURCE_CLASS = "tachiyomi.animeextension.class"
    private const val METADATA_SOURCE_FACTORY = "tachiyomi.animeextension.factory"
    private const val METADATA_NSFW = "tachiyomi.animeextension.nsfw"
    private const val METADATA_HAS_README = "tachiyomi.animeextension.hasReadme"
    private const val METADATA_HAS_CHANGELOG = "tachiyomi.animeextension.hasChangelog"

    const val LIB_VERSION_MIN = 12
    const val LIB_VERSION_MAX = 16

    @Suppress("DEPRECATION")
    private val PACKAGE_FLAGS =
        PackageManager.GET_CONFIGURATIONS or PackageManager.GET_META_DATA or PackageManager.GET_SIGNATURES or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES else 0)

    @SuppressLint("QueryPermissionsNeeded")
    fun loadExtensions(context: Context, path: String?): List<AnimeExtension.Installed> {
        val pkgManager = context.packageManager
        val installedPkgs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pkgManager.getInstalledPackages(
                PackageManager.PackageInfoFlags.of(PACKAGE_FLAGS.toLong())
            )
        } else {
            pkgManager.getInstalledPackages(PACKAGE_FLAGS)
        }

        val sharedExtPkgs = installedPkgs.asSequence().filter(::isPackageAnExtension).map { AnimeExtensionInfo(it, isShared = true) }.toList()

        try {
            Logger.log(
                "Path for private extensions: ${path ?: "default internal storage"}", LogLevel.INFO
            )
            val defaultDir = File(context.filesDir, "aniyomi-extensions/Anime")
            val externalDir = path?.let { File(it) } ?: defaultDir
            val privateDir = File(context.filesDir, "aniyomi-extensions/Anime")

            if (!privateDir.exists()) {
                privateDir.mkdirs()
            }

            Logger.log(
                "Looking for private extensions in ${externalDir.absolutePath}",
                LogLevel.INFO
            )

            val externalFiles = externalDir.listFiles()
                ?.filter { it.isFile && it.extension == "apk" }
                ?: emptyList()

            val privateFiles = privateDir.listFiles()
                ?.associateBy { it.name }
                ?: emptyMap()

            externalFiles.forEach { src ->
                val dst = File(privateDir, src.name)

                val shouldCopy = !dst.exists() || src.length() != dst.length()

                if (shouldCopy) {
                    val tmp = File(privateDir, "${src.name}.tmp")

                    tmp.outputStream().use { out ->
                        src.inputStream().use { it.copyTo(out) }
                    }

                    if (!tmp.renameTo(dst)) {
                        tmp.delete()
                        throw IOException("Failed to finalize ${dst.name}")
                    }

                    dst.setReadOnly()
                }
            }
            privateFiles.forEach { (name, file) ->
                val stillExists = externalFiles.any { it.name == name }
                if (!stillExists) {
                    file.delete()
                }
            }

            val privateExtPkgs = privateDir.listFiles()?.asSequence()?.filter { it.isFile && it.extension == "apk" }?.mapNotNull { apk ->
                pkgManager.getPackageArchiveInfo(apk.absolutePath, PACKAGE_FLAGS)?.apply { applicationInfo?.fixBasePaths(apk.absolutePath) }
            }?.filter(::isPackageAnExtension)?.map { AnimeExtensionInfo(it, isShared = false) }?.toList() ?: emptyList()

            val privateByPkg = privateExtPkgs.associateBy { it.packageInfo.packageName }

            val extPkgs = (sharedExtPkgs + privateExtPkgs).distinctBy { it.packageInfo.packageName }.mapNotNull { shared ->
                selectExtensionPackage(shared, privateByPkg[shared.packageInfo.packageName])
            }


            val extensions = extPkgs.map { loadExtension(context, it) }.filterIsInstance<AnimeLoadResult.Success>().map { it.extension }

            Logger.log(
                "Found ${privateExtPkgs.size} private and ${sharedExtPkgs.size} shared extensions, loaded ${extensions.size}", LogLevel.INFO
            )

            return extensions
        } catch (e: Exception) {
            Logger.log("Extension load failed: ${e.message}", LogLevel.ERROR)
            return emptyList()
        }
    }


    private fun loadExtension(context: Context, extensionInfo: AnimeExtensionInfo): AnimeLoadResult {
        val pkgManager = context.packageManager

        val pkgInfo = extensionInfo.packageInfo
        val appInfo = pkgInfo.applicationInfo!!
        val pkgName = pkgInfo.packageName

        val extName = pkgManager.getApplicationLabel(appInfo).toString().substringAfter("Aniyomi: ")
        val versionName = pkgInfo.versionName
        val versionCode = PackageInfoCompat.getLongVersionCode(pkgInfo)

        if (versionName.isNullOrEmpty()) {
            return AnimeLoadResult.Error
        }

        // Validate lib version
        val libVersion = versionName.substringBeforeLast('.').toDoubleOrNull()
        if (libVersion == null || libVersion < LIB_VERSION_MIN || libVersion > LIB_VERSION_MAX) {

            return AnimeLoadResult.Error
        }


        val isNsfw = appInfo.metaData.getInt(METADATA_NSFW) == 1
        val hasReadme = appInfo.metaData.getInt(METADATA_HAS_README, 0) == 1
        val hasChangelog = appInfo.metaData.getInt(METADATA_HAS_CHANGELOG, 0) == 1

        val parent = context.classLoader!!

        val classLoader = try {
            ChildFirstPathClassLoader(appInfo.sourceDir, null, parent)
        } catch (e: Throwable) {
            Logger.log(
                "Failed to create class loader for extension ${appInfo.packageName}: ${e.message}\n${e.stackTraceToString()}", LogLevel.ERROR
            )
            return AnimeLoadResult.Error
        }

        val sources = appInfo.metaData.getString(METADATA_SOURCE_CLASS)!!.split(";").map {
            val sourceClass = it.trim()
            if (sourceClass.startsWith(".")) {
                pkgInfo.packageName + sourceClass
            } else {
                sourceClass
            }
        }.flatMap {
            try {
                when (val obj = Class.forName(it, false, classLoader).getDeclaredConstructor().newInstance()) {
                    is AnimeSource -> listOf(obj)
                    is AnimeSourceFactory -> obj.createSources()
                    else -> throw Exception("Unknown source class type: ${obj.javaClass}")
                }
            } catch (_: LinkageError) {
                try {
                    val fallBackClassLoader = PathClassLoader(appInfo.sourceDir, null, parent)
                    when (val obj = Class.forName(
                        it,
                        false,
                        fallBackClassLoader,
                    ).getDeclaredConstructor().newInstance()) {
                        is AnimeSource -> {
                            listOf(obj)
                        }

                        is AnimeSourceFactory -> obj.createSources()
                        else -> throw Exception("Unknown source class type: ${obj.javaClass}")
                    }
                } catch (e: Throwable) {
                    Logger.log(
                        "Failed to load source class $it from extension ${appInfo.packageName}: ${e.message}\n${e.stackTraceToString()}", LogLevel.ERROR
                    )
                    return AnimeLoadResult.Error
                }
            } catch (e: Throwable) {
                Logger.log(
                    "Failed to load source class $it from extension ${appInfo.packageName}: ${e.message}\n${e.stackTraceToString()}", LogLevel.ERROR
                )
                return AnimeLoadResult.Error
            }
        }

        val langs = sources.filterIsInstance<AnimeCatalogueSource>().map { it.lang }.toSet()
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
            pkgFactory = appInfo.metaData.getString(METADATA_SOURCE_FACTORY),
            isUnofficial = true,
            iconUrl = context.getApplicationIcon(pkgInfo),
                isShared = extensionInfo.isShared,
        )
        return AnimeLoadResult.Success(extension)
    }

    private fun selectExtensionPackage(shared: AnimeExtensionInfo?, private: AnimeExtensionInfo?): AnimeExtensionInfo? {
        when {
            private == null && shared != null -> return shared
            shared == null && private != null -> return private
            shared == null && private == null -> return null
        }

        return if (PackageInfoCompat.getLongVersionCode(shared!!.packageInfo) >= PackageInfoCompat.getLongVersionCode(private!!.packageInfo)) {
            shared
        } else {
            private
        }
    }

    private fun isPackageAnExtension(pkgInfo: PackageInfo): Boolean = pkgInfo.reqFeatures.orEmpty().any { it.name == EXTENSION_FEATURE }


    /**
     * On Android 13+ the ApplicationInfo generated by getPackageArchiveInfo doesn't
     * have sourceDir which breaks assets loading (used for getting icon here).
     */
    private fun ApplicationInfo.fixBasePaths(apkPath: String) {
        if (sourceDir == null) {
            sourceDir = apkPath
        }
        if (publicSourceDir == null) {
            publicSourceDir = apkPath
        }
    }

    private data class AnimeExtensionInfo(
        val packageInfo: PackageInfo,
        val isShared: Boolean,
    )

    fun Context.getApplicationIcon(
        packageInfo: PackageInfo
    ): String? {
        return try {
            val appInfo = packageInfo.applicationInfo ?: return null

            appInfo.fixBasePaths(appInfo.sourceDir)

            val bitmap = when (val drawable = appInfo.loadIcon(packageManager)) {
                is BitmapDrawable -> drawable.bitmap
                else -> {
                    val bmp = createBitmap(drawable.intrinsicWidth.coerceAtLeast(1), drawable.intrinsicHeight.coerceAtLeast(1))
                    val canvas = Canvas(bmp)
                    drawable.setBounds(0, 0, canvas.width, canvas.height)
                    drawable.draw(canvas)
                    bmp
                }
            }

            val file = File(cacheDir, "${packageInfo.packageName}_icon.png")
            FileOutputStream(file).use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }

            file.absolutePath
        } catch (e: Exception) {
            Logger.log(
                "Error extracting icon for ${packageInfo.packageName}: ${e.message}", LogLevel.ERROR
            )
            null
        }
    }

}/*fun installPrivateExtensionFile(context: Context, file: File): Boolean {
    val extension = context.packageManager.getPackageArchiveInfo(
        file.absolutePath,
        PACKAGE_FLAGS,
    )
        ?.takeIf { isPackageAnExtension(it) } ?: return false
    val currentExtension = getAnimeExtensionPackageInfoFromPkgName(
        context,
        extension.packageName,
    )

    if (currentExtension != null) {
        if (PackageInfoCompat.getLongVersionCode(extension) <
            PackageInfoCompat.getLongVersionCode(currentExtension)
        ) {
            logcat(LogPriority.ERROR) { "Installed extension version is higher. Downgrading is not allowed." }
            return false
        }

        val extensionSignatures = getSignatures(extension)
        if (extensionSignatures.isNullOrEmpty()) {
            logcat(LogPriority.ERROR) { "Extension to be installed is not signed." }
            return false
        }

        if (!extensionSignatures.containsAll(getSignatures(currentExtension)!!)) {
            logcat(LogPriority.ERROR) { "Installed extension signature is not matched." }
            return false
        }
    }

    val target = File(
       getPrivateExtensionDir(context),
        "${extension.packageName}.${PRIVATE_EXTENSION_EXTENSION}",
    )
    return try {
        target.delete()
        if (currentExtension != null) {

        } else {

        }
        true
    } catch (e: Exception) {

        target.delete()
        false
    }
}*/

