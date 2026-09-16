package com.aayush262.dartotsu_extension_bridge.util

import android.content.pm.PackageInfo
import android.content.pm.Signature
import android.os.Bundle
import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import com.googlecode.d2j.dex.Dex2jar
import com.googlecode.d2j.reader.MultiDexFileReader
import com.googlecode.dex2jar.tools.BaksmaliBaseDexExceptionHandler
import net.dongliu.apk.parser.ApkFile
import net.dongliu.apk.parser.ApkParsers
import net.dongliu.apk.parser.bean.IconFace
import org.w3c.dom.Element
import org.w3c.dom.Node
import xyz.nulldev.androidcompat.pm.InstalledPackage.Companion.toList
import xyz.nulldev.androidcompat.pm.toPackageInfo
import java.io.File
import java.io.FileOutputStream
import java.net.URLClassLoader
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.concurrent.ConcurrentHashMap
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import javax.xml.parsers.DocumentBuilderFactory
import kotlin.collections.asSequence
import kotlin.collections.orEmpty
import kotlin.io.path.Path

object PackageTools {


    /**
     * Convert dex to jar, a wrapper for the dex2jar library.
     *
     * The whole conversion (dex2jar + [BytecodeEditor]) runs against a private
     * temp file and is swapped into place with a single atomic move. The
     * desktop backends call [loadExtensions][com.aayush262.dartotsu_extension_bridge.aniyomi.MangaExtensionLoader.loadExtensions]
     * concurrently (the sidecar fans every request out, and the app polls), so
     * two threads can convert the same APK at once — an in-place write left the
     * jar half-formed and `URLClassLoader` then failed with
     * `ClassNotFoundException` on the source class. With the atomic swap a
     * reader always sees a complete jar (whichever conversion moved last).
     */
    fun dex2jar(
        dexFile: String,
        jarFile: String,
    ) {
        val finalPath = File(jarFile).toPath()
        val parent = finalPath.parent ?: Path("")
        Files.createDirectories(parent)
        val tmp = Files.createTempFile(parent, "dartotsu-d2j-", ".jar")
        try {
            val reader = MultiDexFileReader.open(Files.readAllBytes(File(dexFile).toPath()))
            val handler = BaksmaliBaseDexExceptionHandler()
            Dex2jar
                .from(reader)
                .withExceptionHandler(handler)
                .reUseReg(false)
                .topoLogicalSort()
                .skipDebug(true)
                .optimizeSynchronized(false)
                .printIR(false)
                .noCode(false)
                .skipExceptions(false)
                .dontSanitizeNames(true)
                .to(tmp)
            if (handler.hasException()) {
                Logger.log("dex2jar reported exceptions while converting $dexFile; running bytecode fixups anyway", LogLevel.ERROR)
            }
            BytecodeEditor.fixAndroidClasses(tmp, File(dexFile).toPath())
            Files.move(tmp, finalPath, StandardCopyOption.REPLACE_EXISTING)
        } finally {
            Files.deleteIfExists(tmp)
        }
    }

    fun getPackageInfo(apkFilePath: String): ApkInfo {
        val apk = File(apkFilePath)

        val parsed = ApkFile(apk)

        val packageInfo = ApkParsers.getMetaInfo(apk).toPackageInfo(apk).apply {
            val dbFactory = DocumentBuilderFactory.newInstance()
            val dBuilder = dbFactory.newDocumentBuilder()
            val doc =
                parsed.manifestXml.byteInputStream().use {
                    dBuilder.parse(it)
                }

            applicationInfo.metaData =
                Bundle().apply {
                    val appTag = doc.getElementsByTagName("application").item(0)

                    appTag
                        ?.childNodes
                        ?.toList()
                        .orEmpty()
                        .asSequence()
                        .filter { it.nodeType == Node.ELEMENT_NODE }
                        .map { it as Element }
                        .filter { it.tagName == "meta-data" }
                        .forEach {
                            putString(
                                it.attributes.getNamedItem("android:name").nodeValue,
                                it.attributes.getNamedItem("android:value").nodeValue,
                            )
                        }
                }

            signatures =
                parsed.apkSingers
                    .flatMap { it.certificateMetas }
                    .map { Signature(it.data) }
                    .toTypedArray()
        }

        return ApkInfo(packageInfo, parsed)
    }


    // Concurrent: the desktop loaders call in from several request coroutines
    // at once. A plain mutableMap here threw ConcurrentModificationException
    // and let two loaders race to create a class loader for the same jar.
    val jarLoaderMap = ConcurrentHashMap<String, URLClassLoader>()

    /**
     * Evicts and closes the cached classloader for [jarPath], if any.
     *
     * [jarLoaderMap] is keyed by the jar's file path, which is stable across
     * extension versions — dex2jar names it after the package, not the
     * version — so updating an extension overwrites that same path's
     * *contents* via an atomic move, but a already-cached `URLClassLoader`
     * has its zip central directory built from the old bytes and never
     * notices the file underneath it changed. Reusing it after an update
     * then throws `ClassNotFoundException` for classes that are actually
     * present in the freshly written jar. Callers must invoke this after
     * regenerating a jar and before the next [loadExtensionSources] call.
     */
    fun invalidateClassLoader(jarPath: String) {
        jarLoaderMap.remove(jarPath)?.let {
            try {
                it.close()
            } catch (_: Exception) {
            }
        }
    }

    /**
     * loads the extension main class called [className] from the jar located at [jarPath]
     * It may return an instance of HttpSource or SourceFactory depending on the extension.
     */
    fun loadExtensionSources(
        jarPath: String,
        className: String,
    ): Any {
        try {
            val classLoader = jarLoaderMap.computeIfAbsent(jarPath) {
                ChildFirstURLClassLoader(arrayOf(Path(jarPath).toUri().toURL()))
            }
            val classToLoad = Class.forName(className, false, classLoader)
            return classToLoad.getDeclaredConstructor().newInstance()
        } catch (e: Exception) {
            Logger.log("Failed to load jar with path: $jarPath, error: ${e.message}", LogLevel.ERROR)
            throw e
        }
    }
    fun getClassLoader(jarPath: String): URLClassLoader {
        return jarLoaderMap.computeIfAbsent(jarPath) {
            URLClassLoader(
                arrayOf(Path(jarPath).toUri().toURL()),
                this.javaClass.classLoader
            )
        }
    }
    fun extractIcon(
        apkParser: ApkFile,
        apkFile: File,
        outputDir: File,
        packageName: String
    ): File? {
        try {
            if (!outputDir.exists()) outputDir.mkdirs()

            val iconFile = File(outputDir, "$packageName.png")

            if (iconFile.exists() && iconFile.lastModified() >= apkFile.lastModified()) {
                return iconFile
            }

            val icons = apkParser.allIcons

            if (icons.isNullOrEmpty()) {
                Logger.log("No icons found in APK")
                return null
            }

            val densityPriority = listOf(
                "xxxhdpi", "xxhdpi", "xhdpi", "hdpi", "mdpi", "ldpi"
            )

            val bestIcon = icons
                .filter { it.isFile }
                .sortedWith(
                    compareByDescending<IconFace> {
                        it.path.contains("mipmap")
                    }.thenByDescending {
                        val path = it.path.lowercase()
                        val index = densityPriority.indexOfFirst { d -> path.contains(d) }
                        if (index == -1) 0 else (densityPriority.size - index)
                    }
                )
                .firstOrNull()
                ?: icons.lastOrNull { it.isFile }

            if (bestIcon != null) {
                iconFile.outputStream().use { it.write(bestIcon.data) }
                Logger.log("Icon extracted → ${bestIcon.path}")
                return iconFile
            }

            return null

        } catch (e: Exception) {
            Logger.log("Icon extraction failed: ${e.message}")
            return null
        }
    }
    fun extractAssetsFromApk(apkPath: String, jarPath: String) {
        val apkFile = File(apkPath)
        val jarFile = File(jarPath)

        // Private temp dir + jar so two threads staging the same APK / jar
        // (the loaders run concurrently) can't clobber each other's scratch
        // files; the result is swapped in with one atomic move.
        val assetsFolder = Files.createTempDirectory(
            jarFile.parentFile?.toPath() ?: Path(""),
            "dartotsu-assets-",
        ).toFile()
        val tempJarPath = Files.createTempFile(
            jarFile.parentFile?.toPath() ?: Path(""),
            "dartotsu-assets-", ".jar",
        )

        try {
            ZipInputStream(apkFile.inputStream()).use { zip ->
                generateSequence { zip.nextEntry }.forEach { entry ->
                    if (
                        !entry.isDirectory &&
                        (
                                entry.name == "manifest.json" ||
                                        entry.name.startsWith("assets/") ||
                                        entry.name.startsWith("res/") ||
                                        entry.name == "resources.arsc"
                                )
                    ) {
                        val out = File(assetsFolder, entry.name)
                        out.parentFile.mkdirs()
                        FileOutputStream(out).use { zip.copyTo(it) }
                    }
                }
            }

            ZipInputStream(jarFile.inputStream()).use { jarIn ->
                ZipOutputStream(Files.newOutputStream(tempJarPath)).use { jarOut ->
                    generateSequence { jarIn.nextEntry }.forEach { entry ->
                        if (!entry.name.startsWith("META-INF/")) {
                            jarOut.putNextEntry(ZipEntry(entry.name))
                            jarIn.copyTo(jarOut)
                        }
                    }

                    assetsFolder.walkTopDown().forEach { file ->
                        if (file.isFile) {
                            val name = file.relativeTo(assetsFolder).path.replace("\\", "/")
                            jarOut.putNextEntry(ZipEntry(name))
                            file.inputStream().use { it.copyTo(jarOut) }
                            jarOut.closeEntry()
                        }
                    }
                }
            }

            Files.move(tempJarPath, jarFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
        } finally {
            Files.deleteIfExists(tempJarPath)
            assetsFolder.deleteRecursively()
        }
    }
}
data class ApkInfo(
    val packageInfo: PackageInfo,
    val apkFile: ApkFile
)