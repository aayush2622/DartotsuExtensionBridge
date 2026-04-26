package com.aayush262.dartotsu_extension_bridge.aniyomi.util

import android.content.pm.PackageInfo
import android.content.pm.Signature
import android.os.Bundle
import com.aayush262.dartotsu_extension_bridge.LogLevel
import com.aayush262.dartotsu_extension_bridge.Logger
import com.googlecode.d2j.dex.Dex2jar
import com.googlecode.d2j.reader.MultiDexFileReader
import com.googlecode.dex2jar.tools.BaksmaliBaseDexExceptionHandler
import eu.kanade.tachiyomi.util.system.ChildFirstURLClassLoader
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
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import javax.xml.parsers.DocumentBuilderFactory
import kotlin.collections.asSequence
import kotlin.collections.orEmpty
import kotlin.io.path.Path

object PackageTools {


    /**
     * Convert dex to jar, a wrapper for the dex2jar library
     */
    fun dex2jar(
        dexFile: String,
        jarFile: String,
    ) {
        // adopted from com.googlecode.dex2jar.tools.Dex2jarCmd.doCommandLine
        // source at: https://github.com/DexPatcher/dex2jar/tree/v2.1-20190905-lanchon/dex-tools/src/main/java/com/googlecode/dex2jar/tools/Dex2jarCmd.java

        val jarFilePath = File(jarFile).toPath()
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
            .to(jarFilePath)
        if (!handler.hasException()) {
            BytecodeEditor.fixAndroidClasses(jarFilePath)
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


    val jarLoaderMap = mutableMapOf<String, URLClassLoader>()

    /**
     * loads the extension main class called [className] from the jar located at [jarPath]
     * It may return an instance of HttpSource or SourceFactory depending on the extension.
     */
    fun loadExtensionSources(
        jarPath: String,
        className: String,
    ): Any {
        try {
            Logger.log("Loading jar with path: $jarPath", LogLevel.DEBUG)
            val parent = this.javaClass.classLoader
            val classLoader = jarLoaderMap[jarPath] ?: ChildFirstURLClassLoader(
                arrayOf(Path(jarPath).toUri().toURL()),
                parent
            )
            val classToLoad = Class.forName(className, false, classLoader)

            jarLoaderMap[jarPath] = classLoader

            return classToLoad.getDeclaredConstructor().newInstance()
        } catch (e: Exception) {
            Logger.log("Failed to load jar with path: $jarPath, error: ${e.message}", LogLevel.ERROR)
            throw e
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
                println("No icons found in APK")
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
                println("Icon extracted → ${bestIcon.path}")
                return iconFile
            }

            return null

        } catch (e: Exception) {
            println("Icon extraction failed: ${e.message}")
            return null
        }
    }
    fun extractAssetsFromApk(apkPath: String, jarPath: String) {
        val apkFile = File(apkPath)
        val jarFile = File(jarPath)

        val assetsFolder = File("${apkFile.parent}/${apkFile.nameWithoutExtension}_assets")
        assetsFolder.mkdir()

        ZipInputStream(apkFile.inputStream()).use { zip ->
            generateSequence { zip.nextEntry }.forEach { entry ->
                if (entry.name.startsWith("assets/") && !entry.isDirectory) {
                    val out = File(assetsFolder, entry.name)
                    out.parentFile.mkdirs()
                    FileOutputStream(out).use { zip.copyTo(it) }
                }
            }
        }

        val tempJar = File("${jarFile.parent}/${jarFile.nameWithoutExtension}_temp.jar")

        ZipInputStream(jarFile.inputStream()).use { jarIn ->
            ZipOutputStream(FileOutputStream(tempJar)).use { jarOut ->
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

        jarFile.delete()
        tempJar.renameTo(jarFile)
        assetsFolder.deleteRecursively()
    }
}
data class ApkInfo(
    val packageInfo: PackageInfo,
    val apkFile: ApkFile
)