import groovy.json.JsonOutput
import java.io.File

/*
 * plugin.gradle.kts
 *
 * Responsible for exactly three things:
 *   1. Building the plugin (APK or JAR)
 *   2. Copying the resulting artifact into builds/<pluginName>/
 *   3. Writing <pluginName>-plugin.json describing that artifact
 *
 * This file must never know about git, GitHub, releases, hashes, or
 * version bumping. All of that lives in CI (.github/workflows/build.yml
 * + scripts/prepare_release.py), which patches versionCode/versionName/
 * downloadUrl into the JSON this script produces *after* it's written.
 */

val pluginName = project.name

/*
 * iOS runtime variant.
 *
 * `-PiosRuntime=true` tells the desktop modules to strip Chromium/JCEF/JOGL/JNA
 * and their native payloads from the shadow JAR (see each `*Desktop`
 * build.gradle.kts). The resulting JAR is loadable by the interpreter-only
 * OpenJDK Zero VM the plugin embeds on iOS (`ios/`, `EmbeddedBridge`). This
 * mirrors M-Extension-Server's own `-PiosRuntime=true` switch.
 *
 * A single Gradle invocation only holds one value for a project property, so
 * building both variants means two runs:
 *   ./gradlew buildAllPlugins                    # desktop + android
 *   ./gradlew buildAllPlugins -PiosRuntime=true  # ios
 */
val iosRuntime: Boolean =
    project.findProperty("iosRuntime")?.toString()?.toBoolean() ?: false

data class Artifact(
    val file: File,
    val extension: String,
    val platform: String,
    val type: String,
)

fun requiredProperty(key: String): String =
    project.findProperty(key)?.toString()
        ?: throw GradleException("[$pluginName] Missing required property \"$key\".")

fun optionalProperty(key: String, default: String): String =
    project.findProperty(key)?.toString() ?: default

fun findArtifact(): Artifact {

    val releaseApkDir = layout.projectDirectory
        .dir("build/outputs/apk/release")
        .asFile

    releaseApkDir.listFiles()
        ?.firstOrNull { it.extension == "apk" && it.name.contains("release", true) }
        ?.let { return Artifact(it, "apk", "android", "apk") }

    // -PiosRuntime=true builds the same shadow JAR minus the desktop-only
    // native stack; it targets the embedded OpenJDK Zero VM, not a desktop.
    val jarPlatform = if (iosRuntime) "ios" else "desktop"

    val shadowJar = layout.buildDirectory
        .file("libs/${project.name}-all.jar")
        .get()
        .asFile

    if (shadowJar.exists()) {
        return Artifact(shadowJar, "jar", jarPlatform, "jar")
    }

    val normalJar = layout.buildDirectory
        .file("libs/${project.name}.jar")
        .get()
        .asFile

    if (normalJar.exists()) {
        return Artifact(normalJar, "jar", jarPlatform, "jar")
    }

    throw GradleException("[$pluginName] Could not locate a built APK or JAR.")
}

fun outputDirectory(): File =
    File(rootProject.projectDir, "builds/$pluginName").apply { mkdirs() }

fun buildMetadata(artifact: Artifact, outputFile: File): LinkedHashMap<String, Any?> {

    val json = linkedMapOf<String, Any?>()

    json["name"] = pluginName
    // Placeholder version — CI overwrites this once it knows whether
    // the artifact actually changed relative to the previous release.
    json["versionCode"] = 1
    json["versionName"] = "1.0.0"
    json["description"] = optionalProperty("pluginDescription", "N/A")
    json["author"] = requiredProperty("pluginAuthor")
    json["createdAt"] = System.currentTimeMillis()
    json["platform"] = artifact.platform
    json["type"] = artifact.type
    json["fileName"] = outputFile.name
    json["fileSize"] = outputFile.length()
    // Filled in by CI once the release/tag/host is known.
    json["downloadUrl"] = ""

    return json
}

tasks.register("buildPlugin") {

    group = "plugin"
    description = "Build plugin artifact and metadata for $pluginName"

    dependsOn(
        when {
            project.plugins.hasPlugin("com.android.application") -> "assembleRelease"
            tasks.findByName("shadowJar") != null -> "shadowJar"
            else -> "jar"
        }
    )

    doLast {

        val artifact = findArtifact()
        val outputDir = outputDirectory()
        // Keep the ios artifact next to the desktop one instead of overwriting
        // it: builds/<name>/<name>-plugin-ios.jar + <name>-plugin-ios.json.
        val suffix = if (iosRuntime) "-ios" else ""
        val destination =
            File(outputDir, "$pluginName-plugin$suffix.${artifact.extension}")
        val metadataFile = File(outputDir, "$pluginName-plugin$suffix.json")

        artifact.file.copyTo(destination, overwrite = true)

        metadataFile.writeText(
            JsonOutput.prettyPrint(
                JsonOutput.toJson(buildMetadata(artifact, destination))
            )
        )

        logger.lifecycle("")
        logger.lifecycle("========================================")
        logger.lifecycle("Plugin   : $pluginName")
        logger.lifecycle("Artifact : ${destination.name}")
        logger.lifecycle("Platform : ${artifact.platform}")
        logger.lifecycle("Output   : ${outputDir.absolutePath}")
        logger.lifecycle("========================================")
        logger.lifecycle("")
    }
}