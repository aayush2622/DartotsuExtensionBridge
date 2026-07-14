import groovy.json.JsonOutput
import groovy.json.JsonSlurper

plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.shadow) apply false
    alias(libs.plugins.android.kmp.library) apply false
    alias(libs.plugins.kotlinMultiplatform) apply false
    alias(libs.plugins.android.lint) apply false
}
tasks.register<Delete>("clean") {
    delete(layout.buildDirectory)
}

rootProject.tasks.register("buildAllPlugins") {
    dependsOn(
        rootProject.subprojects.mapNotNull {
            it.tasks.findByName("buildPlugin")
        }
    )

    finalizedBy("generatePluginIndex")
}



tasks.register("generatePluginIndex") {
    group = "plugin"
    description = "Generate plugins.json containing all plugin metadata"

    doLast {
        val buildsDir = File(rootProject.projectDir, "builds")

        if (!buildsDir.exists()) return@doLast

        val plugins = mutableListOf<Map<String, Any?>>()

        buildsDir.listFiles()?.filter { it.isDirectory }?.forEach { dir ->
            dir.listFiles()?.filter {
                it.extension == "json" && it.name.endsWith("-plugin.json")
            }?.forEach { jsonFile ->
                try {
                    @Suppress("UNCHECKED_CAST") val map = JsonSlurper().parse(jsonFile) as Map<String, Any?>

                    plugins += map
                } catch (e: Exception) {
                    println("Failed to read ${jsonFile.name}: ${e.message}")
                }
            }
        }

        val output = File(buildsDir, "plugins.json")
        output.writeText(
            JsonOutput.prettyPrint(JsonOutput.toJson(plugins))
        )

        println("Generated ${output.absolutePath} (${plugins.size} plugins)")
    }
}