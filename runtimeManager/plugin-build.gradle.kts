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
fun prop(name: String, default: String): String {
    val value = project.extensions.extraProperties
        .takeIf { it.has(name) }
        ?.get(name)?.toString()
        ?: project.findProperty(name)?.toString()
        ?: default

    if (value.isBlank()) {
        throw GradleException(
            """
            [$pluginName] Missing required property: "$name"

            👉 Add this to your plugin build.gradle.kts:

            extra.apply {
                set("pluginDescription", "Your plugin description")
                set("pluginAuthor", "your_name")
                set("pluginRepo", "https://your.repo/url") // Optional only if you want to specify a custom repo URL for downloads, otherwise it will attempt to auto-detect from git config
            }
            """.trimIndent()
        )
    }

    return value
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

        val fileSize = existingFile.length()

        val description = prop("pluginDescription", "N/A")
        val author = prop("pluginAuthor", "")
        val baseRepo = prop("pluginRepo", getGitRepoUrl())
        val repo = normalizeRepo(baseRepo)
        val json = """
            {
              "name": "$pluginName",
              "versionCode": $finalCode,
              "versionName": "$finalName",
              "description": "$description",
              "author": "$author",
              "createdAt": ${System.currentTimeMillis()},
              "type": "${artifact.type}",
              "fileName": "$pluginName-plugin.$extension",
              "fileSize": $fileSize,
              "downloadUrl": "$repo/$pluginName/$pluginName-plugin.$extension",
              "platform": "${if (artifact.type == "apk") "android" else "desktop"}"
            }
        """.trimIndent()

        jsonFile.writeText(json)
    }
}

fun getGitRepoUrl(): String {
    return try {
        val process = ProcessBuilder("git", "config", "--get", "remote.origin.url")
            .directory(rootProject.projectDir)
            .redirectErrorStream(true)
            .start()

        val url = process.inputStream.bufferedReader().readText().trim()

        if (url.isBlank()) return ""

        when {
            url.startsWith("git@") -> {
                url.replace("git@", "https://")
                    .replace(":", "/")
                    .removeSuffix(".git")
            }
            else -> url.removeSuffix(".git")
        }
    } catch (_: Exception) {
        ""
    }
}
fun detectGitBranch(): String? {
    return try {
        val process = ProcessBuilder("git", "rev-parse", "--abbrev-ref", "HEAD")
            .directory(rootProject.projectDir)
            .redirectErrorStream(true)
            .start()

        process.inputStream.bufferedReader().readText().trim()
            .takeIf { it.isNotBlank() }
    } catch (_: Exception) {
        null
    }
}
fun normalizeRepo(baseRepoInput: String): String {
    val baseRepo = baseRepoInput.trim().removeSuffix("/")

    if (baseRepo.isBlank()) {
        throw GradleException("[$pluginName] Repo URL is empty")
    }

    if (baseRepo.contains("raw.githubusercontent.com")) {
        val cleaned = baseRepo.trim().removeSuffix("/")
        val parts = cleaned
            .substringAfter("raw.githubusercontent.com/")
            .split("/")
            .filter { it.isNotBlank() }

        if (parts.size < 2) {
            throw GradleException("[$pluginName] Invalid raw GitHub URL: $baseRepo")
        }

        val user = parts[0]
        val repo = parts[1]

        val branch = when {
            parts.size >= 3 -> parts[2]
            else -> detectGitBranch() ?: "main"
        }

        val remainingPath = if (parts.size > 3) {
            parts.drop(3).joinToString("/")
        } else ""

        val finalPath = when {
            remainingPath.contains("runtimeManager/builds") -> remainingPath
            remainingPath.isNotBlank() -> "$remainingPath/runtimeManager/builds"
            else -> "runtimeManager/builds"
        }

        return "https://raw.githubusercontent.com/$user/$repo/$branch/$finalPath"
    }
    val httpsRepo = when {
        baseRepo.startsWith("git@") -> {
            baseRepo
                .replace("git@", "https://")
                .replace(":", "/")
        }
        else -> baseRepo
    }.removeSuffix(".git")

    val branch = detectGitBranch() ?: "main"

    if (httpsRepo.contains("github.com")) {

        val path = httpsRepo.substringAfter("github.com/")

        val segments = path.split("/").toMutableList()

        if (segments.size < 2) {
            throw GradleException("[$pluginName] Invalid GitHub repo: $httpsRepo")
        }

        val user = segments[0]
        val repo = segments[1]

        val subPath = when {
            segments.contains("tree") -> {
                val idx = segments.indexOf("tree")
                segments.drop(idx + 2).joinToString("/")
            }
            segments.contains("blob") -> {
                val idx = segments.indexOf("blob")
                segments.drop(idx + 2).joinToString("/")
            }
            else -> ""
        }

        val finalSubPath = if (subPath.isNotBlank()) "$subPath/" else ""

        return "https://raw.githubusercontent.com/$user/$repo/$branch/${finalSubPath}runtimeManager/builds"
    }


    return if (httpsRepo.contains("gitlab")) {
        "$httpsRepo/-/raw/$branch/runtimeManager/builds"
    } else {
        // Forgejo / Gitea / others
        "$httpsRepo/raw/branch/$branch/runtimeManager/builds"
    }
}