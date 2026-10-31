import com.android.build.gradle.internal.tasks.factory.dependsOn

extra.apply {
    set("pluginAuthor", "aayush262")
    set(
        "pluginDescription",
        "The libraries and runtime shared by every desktop plugin (kotlin, okhttp, jsoup, ICU, dex2jar, the Android compat layer). Installed once; the desktop plugins load it on their classpath.",
    )
}

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.shadow)
}

dependencies {
    api(projects.libraries.commonDesktopLib)
}

tasks.shadowJar {
    archiveClassifier.set("all")
    exclude(
        "**/*.pom",
        "**/*.pom.*",
    )
    mergeServiceFiles()
    isZip64 = true
    isReproducibleFileOrder = true
    isPreserveFileTimestamps = false
}

apply(from = "$rootDir/plugin-build.gradle.kts")

tasks.jar { enabled = false }

tasks.build.dependsOn(tasks.shadowJar)
