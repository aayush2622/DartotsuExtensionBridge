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
}