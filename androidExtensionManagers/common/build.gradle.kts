plugins {
    id("com.android.library")
    kotlin("android")
}

group = "com.aayush262.dartotsu_extension_bridge"
version = "1.0"

android {
    namespace = "com.aayush262.dartotsu_extension_bridge.common"
    compileSdk = 36

    defaultConfig {
        minSdk = 21
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        jvmToolchain(17)
    }
}
java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}