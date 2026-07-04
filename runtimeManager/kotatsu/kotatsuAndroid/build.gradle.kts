plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.serialization)
}


android {
    namespace = "com.aayush262.plugin"

    compileSdk = 37

    defaultConfig {
        applicationId = "com.aayush262.dartotsu_extension_bridge.kotatsu_plugin"
        minSdk = libs.versions.minSdk.get().toInt()
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
    implementation(projects.kotatsu.kotatsuCommon)
}

extra.apply {
    set("pluginAuthor", "aayush262/Ryan")
    set("pluginDescription", "A plugin that allows you to run kotatsu extensions on android")
}

apply(from = "$rootDir/plugin-build.gradle.kts")

tasks.register("buildAndInstall") {
    dependsOn(":kotatsu:kotatsuAndroid:assembleDebug")
    finalizedBy(":kotatsu:kotatsuAndroid:installDebug")
}


