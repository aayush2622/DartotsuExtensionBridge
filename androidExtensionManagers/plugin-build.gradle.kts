import java.io.File
import java.security.MessageDigest
import groovy.json.JsonSlurper

val pluginName = project.name

fun hash(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    val bytes = file.readBytes()
    val hashBytes = digest.digest(bytes)
    return hashBytes.joinToString("") { "%02x".format(it) }
}

fun incrementVersion(name: String): String {
    val parts = name.split(".").map { it.toInt() }.toMutableList()
    while (parts.size < 3) parts.add(0)
    parts[2] += 1
    return parts.joinToString(".")
}

fun loadVersion(): Pair<Int, String> {
    val jsonFile = File(
        rootProject.projectDir,
        "builds/$pluginName/$pluginName-plugin.json"
    )

    if (!jsonFile.exists()) {
        return 1 to "1.0.0"
    }

    return try {
        val json = JsonSlurper().parseText(jsonFile.readText()) as Map<*, *>

        val code = (json["versionCode"] as? Number)?.toInt() ?: 1
        val name = json["versionName"] as? String ?: "1.0.0"

        code to name

    } catch (e: Exception) {
        println("⚠️ Failed to read version JSON, fallback to default")
        1 to "1.0.0"
    }
}

tasks.register("buildPlugin") {

    group = "plugin"
    description = "Build plugin APK + JSON for $pluginName"

    var finalCode = 1
    var finalName = "1.0.0"

    dependsOn("assembleRelease")

    doLast {

        val apkDir = layout.projectDirectory.dir("build/outputs/apk/release")

        val outputDir = File(
            rootProject.projectDir,
            "builds/$pluginName"
        ).apply { mkdirs() }

        val newApk = apkDir.asFile.listFiles()
            ?.firstOrNull { it.name.contains("release") && it.extension == "apk" }
            ?: throw RuntimeException("❌ Release APK not found")

        val existingApk = File(outputDir, "$pluginName-plugin.apk")

        val (oldCode, oldName) = loadVersion()

        val hasChanged = if (existingApk.exists()) {
            hash(existingApk) != hash(newApk)
        } else {
            true
        }

        if (hasChanged) {
            finalCode = oldCode + 1
            finalName = incrementVersion(oldName)

            println("🔼 [$pluginName] APK changed → bumping version to $finalName ($finalCode)")

            newApk.copyTo(existingApk, overwrite = true)
        } else {
            finalCode = oldCode
            finalName = oldName

            println("⏸ [$pluginName] No changes detected → version unchanged")
        }

        val jsonFile = File(outputDir, "$pluginName-plugin.json")

        val json = """
            {
              "name": "$pluginName",
              "versionCode": $finalCode,
              "versionName": "$finalName",
              "apk": "https://raw.githubusercontent.com/aayush2622/DartotsuExtensionBridge/master/androidExtensionManagers/builds/$pluginName/$pluginName-plugin.apk"
            }
        """.trimIndent()

        jsonFile.writeText(json)

        println("[$pluginName] done")
        println("APK: ${existingApk.absolutePath}")
        println("JSON: ${jsonFile.absolutePath}")
    }
}