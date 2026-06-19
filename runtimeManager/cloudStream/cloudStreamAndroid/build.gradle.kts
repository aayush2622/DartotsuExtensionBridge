plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.serialization)
}
extra.apply {
    set("pluginAuthor", "aayush262/Ryan")
    set("pluginDescription", "A plugin that allows you to run cloudstream extensions on android")
}

apply(from = "$rootDir/plugin-build.gradle.kts")

android {
    namespace = "com.ryan.cloudStrean_plugin"

    compileSdk = 37

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
    implementation(cloudStreamAndroid.injekt.core)
    implementation(cloudStreamAndroid.nicehttp)

    implementation(cloudStreamAndroid.jackson.databind)
    implementation(cloudStreamAndroid.jackson.kotlin)

    implementation(cloudStreamAndroid.fuzzywuzzy)
    implementation(cloudStreamAndroid.preference.ktx)

    implementation(cloudStreamAndroid.coroutines.core)

    implementation(cloudStreamAndroid.newpipe.extractor)
    implementation(cloudStreamAndroid.rhino)

    implementation(cloudStreamAndroid.tmdb.java)

    implementation(cloudStreamAndroid.retrofit)
    implementation(cloudStreamAndroid.retrofit.jackson)

    implementation(projects.libraries.commonLib)
}