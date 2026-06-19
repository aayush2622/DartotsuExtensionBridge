import com.android.build.gradle.internal.tasks.factory.dependsOn

extra.apply {
    set("pluginAuthor", "aayush262")
    set("pluginDescription", "A plugin that allows you to run Aniyomi extensions on desktop using a custom runtime manager.")
    set("pluginRepo", "https://raw.githubusercontent.com/aayush2622/DartotsuExtensionBridge/master/runtimeManager/builds")
}

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.shadow)
}

dependencies {
    implementation(projects.aniyomi.aniyomiCommon)
}

tasks.shadowJar {
    archiveClassifier.set("all")
    exclude(
        "META-INF/**",
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

