import com.android.build.gradle.internal.tasks.factory.dependsOn

extra.apply {
    set("pluginAuthor", "aayush262")
    set("pluginDescription", "A plugin that allows you to run ireader extensions on desktop")
}
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.shadow)
}

dependencies {
    implementation(projects.ireader.ireaderCommon)
}
kotlin {
    jvmToolchain(21)
}
java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(21))
    }
}
tasks.shadowJar {
    archiveClassifier.set("all")
    exclude(
        "**/*.pom",
        "**/*.pom.*"
    )
    manifest {
        attributes(
            "Main-Class" to
                    "com.aayush262.dartotsu_extension_bridge.Main"
        )
    }
    mergeServiceFiles()
    isZip64 = true
}

apply(from = "$rootDir/plugin-build.gradle.kts")

tasks.jar { enabled = false }

tasks.build.dependsOn(tasks.shadowJar)
