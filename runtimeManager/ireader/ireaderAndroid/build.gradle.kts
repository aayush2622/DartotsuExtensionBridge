plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.serialization)
}


android {
    namespace = "com.aayush262.plugin"

    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.aayush262.dartotsu_extension_bridge.ireader_plugin"
        minSdk = 26
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.toVersion(libs.versions.java.get())
        targetCompatibility = JavaVersion.toVersion(libs.versions.java.get())
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
        debug {
            isMinifyEnabled = false
        }
    }
}
dependencies {
    implementation(projects.ireader.ireaderCommon)
}

extra.apply {
    set("pluginAuthor", "aayush262")
    set("pluginDescription", "A plugin that allows you to run ireader extensions on android")
}

apply(from = "$rootDir/plugin-build.gradle.kts")

tasks.register("buildAndInstall") {
    dependsOn(":ireader:ireaderAndroid:assembleDebug")
    finalizedBy(":ireader:ireaderAndroid:installDebug")
}


