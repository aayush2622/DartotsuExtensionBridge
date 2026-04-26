plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}
extra.apply {
    set("pluginAuthor", "aayush262")
    set("pluginDescription", "A plugin that allows you to run Aniyomi extensions on android")
}

apply(from = "$rootDir/plugin-build.gradle.kts")

android {
    namespace = "com.aayush262.plugin"

    compileSdk = 36

    defaultConfig {
        applicationId = "com.aayush262.dartotsu.aniyomi_plugin"
        minSdk = 21
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            isMinifyEnabled = false
        }
    }

}

tasks.register("buildAndInstall") {
    dependsOn(":aniyomi:assembleDebug")
    finalizedBy(":aniyomi:installDebug")
}

kotlin {
    jvmToolchain(17)
    compilerOptions {
        freeCompilerArgs.add("-Xcontext-receivers")

    }
}

dependencies {

    implementation(aniyomiCommon.jsoup)

    implementation(aniyomiCommon.serialization.json.okio)
    implementation(aniyomiCommon.serialization.protobuf)
    implementation(aniyomiCommon.serialization.json)

    implementation(aniyomiCommon.okhttp)
    implementation(aniyomiCommon.okhttp.logging)
    implementation(aniyomiCommon.okhttp.doh)
    implementation(aniyomiCommon.okhttp.brotli)

    implementation(aniyomiCommon.okio)
    implementation(aniyomiCommon.gson)
    implementation(aniyomiCommon.coroutines.core)
    implementation(aniyomiCommon.rxjava)

    implementation(aniyomiAndroid.rxandroid)
    implementation(aniyomiAndroid.injekt.core)
    implementation(aniyomiAndroid.androidx.core.ktx)
    implementation(aniyomiAndroid.compose.runtime.android)
    implementation(aniyomiAndroid.androidx.preference.ktx)

    implementation(aniyomiAndroid.quickjs.android)

    implementation(aniyomiAndroid.commons.text)

    compileOnly(project(":common"))
}