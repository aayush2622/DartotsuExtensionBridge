import com.android.build.gradle.internal.tasks.factory.dependsOn

extra.apply {
    set("pluginAuthor", "aayush262")
    set("pluginDescription", "A plugin that allows you to run Aniyomi extensions on desktop using a custom runtime manager.")
    }

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.shadow)
}

// -PiosRuntime=true → strip the desktop-only Chromium/JOGL/JNA stack so the
// JAR loads under the embedded interpreter-only OpenJDK Zero VM on iOS.
val iosRuntime = providers.gradleProperty("iosRuntime").map(String::toBoolean).getOrElse(false)

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

    if (iosRuntime) {
        dependencies {
            exclude(dependency("org.jetbrains.intellij.deps.jcef:jcef:.*"))
            exclude(dependency("org.jogamp.jogl:.*"))
            exclude(dependency("org.jogamp.gluegen:.*"))
            exclude(dependency("net.java.dev.jna:jna:.*"))
            exclude(dependency("net.java.dev.jna:jna-platform:.*"))
        }
        exclude(
            "org/cef/**", "org/jogamp/**", "com/jogamp/**", "jogamp/**",
            "com/sun/jna/**", "native/**", "jni/**",
            "**/*.dll", "**/*.dylib", "**/*.so", "**/*.jnilib",
            "darwin*/**", "win32-*/**", "linux-*/**",
            "AndroidManifest.xml", "resources.arsc", "res/**",
        )
    }
}

apply(from = "$rootDir/plugin-build.gradle.kts")

tasks.jar { enabled = false }

tasks.build.dependsOn(tasks.shadowJar)

