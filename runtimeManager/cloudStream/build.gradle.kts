plugins {
    id("com.android.application")
    kotlin("android")
    kotlin("plugin.serialization")
}

apply(from = "$rootDir/plugin-build.gradle.kts")

android {
    namespace = "com.ryan.cloudStrean_plugin"

    compileSdk = 36

    defaultConfig {
        applicationId = "com.ryan.cloudStrean_plugin"
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
    implementation("com.github.Blatzar:NiceHttp:0.4.16")
    implementation("com.fasterxml.jackson.core:jackson-databind:2.13.1")
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin:2.13.1")
    implementation("me.xdrop:fuzzywuzzy:1.4.0")
    implementation("com.squareup.okhttp3:okhttp:5.0.0-alpha.14")
    implementation("androidx.preference:preference-ktx:1.2.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("com.github.TeamNewPipe:NewPipeExtractor:v0.24.4")
    implementation("org.mozilla:rhino:1.7.15")
    implementation("com.google.code.gson:gson:2.11.0")
    implementation("com.uwetrottmann.tmdb2:tmdb-java:2.10.0")
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.retrofit2:converter-jackson:2.11.0")

    compileOnly(project(":common"))
}