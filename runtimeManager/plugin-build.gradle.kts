import java.io.File
import java.security.MessageDigest
import groovy.json.JsonSlurper

val pluginName = project.name

fun hash(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    val hashBytes = digest.digest(file.readBytes())
    return hashBytes.joinToString("") { "%02x".format(it) }
}

fun incrementVersion(name: String): String {
    val parts = name.split(".").map { it.toIntOrNull() ?: 0 }.toMutableList()
    while (parts.size < 3) parts.add(0)
    parts[2] += 1
    return parts.joinToString(".")
}

fun loadVersion(): Pair<Int, String> {
    val jsonFile = File(
        rootProject.projectDir,
        "builds/$pluginName/$pluginName-plugin.json"
    )

    if (!jsonFile.exists()) return 1 to "1.0.0"

    return try {
        val json = JsonSlurper().parseText(jsonFile.readText()) as Map<*, *>
        val code = (json["versionCode"] as? Number)?.toInt() ?: 1
        val name = json["versionName"] as? String ?: "1.0.0"
        code to name
    } catch (_: Exception) {
        1 to "1.0.0"
    }
}

data class Artifact(
    val file: File,
    val type: String
)

fun findArtifact(): Artifact {
    val apkDir = layout.projectDirectory.dir("build/outputs/apk/release").asFile
    val apk = apkDir.listFiles()
        ?.firstOrNull { it.extension == "apk" && it.name.contains("release") }

    if (apk != null) {
        return Artifact(apk, "apk")
    }

    val shadowJarTask = tasks.findByName("shadowJar")
    if (shadowJarTask != null) {
        val shadowJarFile = layout.buildDirectory.file("libs/${project.name}-all.jar").get().asFile
        if (shadowJarFile.exists()) {
            return Artifact(shadowJarFile, "jar")
        }
    }

    val jarFile = layout.buildDirectory.file("libs/${project.name}.jar").get().asFile
    if (jarFile.exists()) {
        return Artifact(jarFile, "jar")
    }

    val customJar = File(
        rootProject.projectDir,
        "builds/$pluginName/$pluginName.jar"
    )
    if (customJar.exists()) {
        return Artifact(customJar, "jar")
    }

    throw RuntimeException("No APK or JAR found for $pluginName")
}

tasks.register("buildPlugin") {

    group = "plugin"
    description = "Build plugin artifact + JSON for $pluginName"

    dependsOn(
        when {
            project.plugins.hasPlugin("com.android.application") -> "assembleRelease"
            tasks.findByName("shadowJar") != null -> "shadowJar"
            else -> "jar"
        }
    )

    doLast {

        val outputDir = File(
            rootProject.projectDir,
            "builds/$pluginName"
        ).apply { mkdirs() }

        val artifact = findArtifact()

        val extension = if (artifact.type == "apk") "apk" else "jar"
        val newFile = artifact.file
        val existingFile = File(outputDir, "$pluginName-plugin.$extension")

        val (oldCode, oldName) = loadVersion()

        val hasChanged = if (existingFile.exists()) {
            hash(existingFile) != hash(newFile)
        } else {
            true
        }

        val finalCode: Int
        val finalName: String

        if (hasChanged) {
            finalCode = oldCode + 1
            finalName = incrementVersion(oldName)
            newFile.copyTo(existingFile, overwrite = true)
            println("[$pluginName] APK changed → bumping version to $finalName ($finalCode)")
        } else {
            finalCode = oldCode
            finalName = oldName
            println("[$pluginName] No changes detected → version unchanged")
        }


        val jsonFile = File(outputDir, "$pluginName-plugin.json")

        val json = """
            {
              "name": "$pluginName",
              "versionCode": $finalCode,
              "versionName": "$finalName",
              "${artifact.type}": "https://raw.githubusercontent.com/aayush2622/DartotsuExtensionBridge/master/androidExtensionManagers/builds/$pluginName/$pluginName-plugin.$extension"
            }
        """.trimIndent()

        jsonFile.writeText(json)
    }
}