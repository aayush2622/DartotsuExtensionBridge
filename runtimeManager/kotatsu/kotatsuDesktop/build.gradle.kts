import com.android.build.gradle.internal.tasks.factory.dependsOn

extra.apply {
    set("pluginAuthor", "aayush262/Ryan")
    set("pluginDescription", "A plugin that allows you to run kotatsu extensions on desktop")
}
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.shadow)
}



dependencies {
    implementation(projects.kotatsu.kotatsuCommon)
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
