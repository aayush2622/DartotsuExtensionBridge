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
    description = "Cleans the build directory"
    delete(layout.buildDirectory)
}

rootProject.tasks.register("buildAllPlugins") {
    description = "Builds all plugins"
    dependsOn(
        rootProject.subprojects.mapNotNull {
            it.tasks.findByName("buildPlugin")
        }
    )
}

// The slim JAR the iOS embedded OpenJDK Zero VM boots with.
rootProject.tasks.register("buildEmbeddedBridge") {
    group = "plugin"
    description = "Builds libraries/commonDesktopLib/build/libs/embedded-bridge.jar"
    dependsOn(":libraries:commonDesktopLib:embeddedBridgeJar")
}

// Everything a single invocation can produce: desktop + android plugin JARs
// and the embedded-bridge shim. The iOS plugin JARs come from re-running
// `buildAllPlugins -PiosRuntime=true` (a Gradle invocation only holds one
// value for the `iosRuntime` project property).
rootProject.tasks.register("buildEverything") {
    group = "plugin"
    description = "buildAllPlugins + buildEmbeddedBridge (desktop/android variant)"
    dependsOn("buildAllPlugins", "buildEmbeddedBridge")
}

rootProject.tasks.register("printBuildVariants") {
    group = "help"
    description = "Lists the plugin build commands"
    doLast {
        println(
            """
            Plugin build variants
            ---------------------
            Desktop + Android : ./gradlew buildAllPlugins
            iOS               : ./gradlew buildAllPlugins -PiosRuntime=true
            Embedded bridge   : ./gradlew buildEmbeddedBridge
            Desktop + bridge  : ./gradlew buildEverything

            Outputs: builds/<plugin>/<plugin>-plugin[-ios].jar (+ .json)
                     libraries/commonDesktopLib/build/libs/embedded-bridge.jar
            """.trimIndent(),
        )
    }
}
