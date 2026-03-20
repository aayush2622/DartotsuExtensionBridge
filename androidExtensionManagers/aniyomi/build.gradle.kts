plugins {
    id("com.android.application")
    kotlin("android")
    kotlin("plugin.serialization")
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
    implementation("uy.kohesive.injekt:injekt-core:1.16.1")
    implementation("org.jsoup:jsoup:1.21.1")

    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json-okio:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-protobuf:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")

    implementation("com.squareup.okhttp3:okhttp:5.0.0-alpha.14")
    implementation("com.squareup.okhttp3:logging-interceptor:5.0.0-alpha.14")
    implementation("com.squareup.okhttp3:okhttp-dnsoverhttps:5.0.0-alpha.14")
    implementation("com.squareup.okhttp3:okhttp-brotli:5.0.0-alpha.14")

    implementation("com.squareup.okio:okio:3.8.0")
    implementation("io.reactivex:rxjava:1.3.8")
    implementation("io.reactivex:rxandroid:1.2.1")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")

    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.compose.runtime:runtime-android:1.8.3")
    implementation("androidx.preference:preference-ktx:1.2.1")

    implementation("app.cash.quickjs:quickjs-android:0.9.2")

    compileOnly(project(":common"))

    implementation("org.apache.commons:commons-text:1.11.0")
}