package com.aayush262.dartotsu_extension_bridge.kotatsu

import java.io.File
import java.util.zip.ZipFile

object KotatsuJars {
    fun isPluginJar(file: File): Boolean =
        file.isFile && (
            file.name == "plugin.jar" || file.name == "kotatsu_plugin.jar" ||
                (file.extension == "jar" && file.name.contains("kotatsu"))
            )

    fun isTsuki(file: File): Boolean = try {
        ZipFile(file).use { zip ->
            zip.entries().asSequence().any { it.name.startsWith("tsuki/") }
        }
    } catch (_: Exception) {
        false
    }

    fun isUsagiId(sourceId: String): Boolean = sourceId.startsWith("usagi_")
}
