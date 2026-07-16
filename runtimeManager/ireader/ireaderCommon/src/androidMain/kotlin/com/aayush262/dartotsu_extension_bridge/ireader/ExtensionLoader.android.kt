package com.aayush262.dartotsu_extension_bridge.ireader

import android.annotation.SuppressLint
import android.app.Application
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import dalvik.system.DexClassLoader
import ireader.core.http.HttpClients
import ireader.core.prefs.PreferenceStore
import com.aayush262.dartotsu_extension_bridge.ireader.prefs.PrefixedPreferenceStore
import dalvik.system.PathClassLoader
import ireader.core.source.CatalogSource
import ireader.core.source.Dependencies
import ireader.core.source.HttpSource
import org.koin.mp.KoinPlatform.getKoin
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import java.io.File
import java.lang.reflect.Modifier


actual object ExtensionLoader {
    private const val EXTENSION_FEATURE = "ireader.extension"
    actual val plugins = mutableMapOf<Long, CatalogSource>()

    @Suppress("DEPRECATION")
    private val PACKAGE_FLAGS =
        PackageManager.GET_CONFIGURATIONS or PackageManager.GET_META_DATA or PackageManager.GET_SIGNATURES or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES else 0)

    @SuppressLint("WrongConstant")
    actual fun loadExtensions(path: String): List<LoadedExtension> {
        plugins.clear()
        val context = Injekt.get<Context>()
        val pkgManager = context.packageManager
        val installedPkgs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pkgManager.getInstalledPackages(
                PackageManager.PackageInfoFlags.of(PACKAGE_FLAGS.toLong())
            )
        } else {
            pkgManager.getInstalledPackages(PACKAGE_FLAGS)
        }
        val sharedExtPkgs = installedPkgs.asSequence().filter(::isPackageAnExtension).map { ExtensionInfo(it, isShared = true) }.toList()

        val externalDir = File(path)
        val privateDir = File(context.filesDir, "ireader-extensions/Novel")

        if (!privateDir.exists()) {
            privateDir.mkdirs()
        }

        Logger.log(
            "Looking for private extensions in ${externalDir.absolutePath}",

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
                    throw kotlinx.io.IOException("Failed to finalize ${dst.name}")
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
        }?.filter(::isPackageAnExtension)?.map { ExtensionInfo(it, isShared = false) }?.toList() ?: emptyList()

        val privateByPkg = privateExtPkgs.associateBy { it.packageInfo.packageName }

        val extPkgs = (sharedExtPkgs + privateExtPkgs).distinctBy { it.packageInfo.packageName }.mapNotNull { shared ->
            selectExtensionPackage(shared, privateByPkg[shared.packageInfo.packageName])
        }
        return extPkgs.map { loadExtension(context, it) }
    }

    private fun loadExtension(context: Context, extensionInfo: ExtensionInfo): LoadedExtension {
        val pkgInfo = extensionInfo.packageInfo
        val appInfo = pkgInfo.applicationInfo!!
        val description = appInfo.metaData?.getString("source.description").orEmpty()
        val icon = appInfo.metaData?.getString("source.icon").orEmpty()
        val sourceClass = appInfo.metaData?.getString("source.class") ?: error("Missing source.class metadata")

        val className = if (sourceClass.startsWith(".")) {
            pkgInfo.packageName + sourceClass
        } else {
            sourceClass
        }

        val prefs = PrefixedPreferenceStore(
            getKoin().get<PreferenceStore>(), pkgInfo.packageName
        )

        val deps = Dependencies(
            getKoin().get<HttpClients>(), prefs
        )

        val loader = if (extensionInfo.isShared) {
            PathClassLoader(
                appInfo.sourceDir,
                null,
                javaClass.classLoader,
            )
        } else {
            DexClassLoader(
                appInfo.sourceDir,
                File(context.codeCacheDir, "ireader_dex").apply { mkdirs() }.absolutePath,
                null,
                javaClass.classLoader,
            )
        }

        val clazz = Class.forName(
            className, false, loader
        )

        require(!Modifier.isAbstract(clazz.modifiers)) {
            "Source class is abstract: $className"
        }

        val instance = clazz.getDeclaredConstructor(Dependencies::class.java).newInstance(deps)

        require(instance is CatalogSource) {
            "Loaded class $className is not a CatalogSource (${instance::class.java.name})"
        }

        plugins[instance.id] = instance

        return LoadedExtension(
            source = instance,
            packageName = pkgInfo.packageName,
            versionName = pkgInfo.versionName.orEmpty(),
            versionCode = pkgInfo.longVersionCode,
            apkPath = appInfo.sourceDir,
            baseUrl = (instance as? HttpSource)?.baseUrl.orEmpty(),
            icon = icon,
            description = description,
            isShared = extensionInfo.isShared
        )
    }
    private data class ExtensionInfo(
        val packageInfo: PackageInfo,
        val isShared: Boolean,
    )
    private fun selectExtensionPackage(
        shared: ExtensionInfo?,
        private: ExtensionInfo?,
    ): ExtensionInfo? {
        when {
            shared == null -> return private
            private == null -> return shared
        }

        return if (shared.packageInfo.compatVersionCode >= private.packageInfo.compatVersionCode) {
            shared
        } else {
            private
        }
    }
    private fun ApplicationInfo.fixBasePaths(apkPath: String) {
        if (sourceDir == null) {
            sourceDir = apkPath
        }
        if (publicSourceDir == null) {
            publicSourceDir = apkPath
        }
    }

    private fun isPackageAnExtension(pkgInfo: PackageInfo): Boolean = pkgInfo.reqFeatures.orEmpty().any { it.name == EXTENSION_FEATURE }

    private val PackageInfo.compatVersionCode: Long
        get() =
            longVersionCode
}