import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.jvm)
}

group = "com.aayush262"
version = "1.0"

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
        freeCompilerArgs.add("-Xcontext-receivers")
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

dependencies {
    api(projects.libraries.commonLib)
    api(commonDesktopLib.bundles.desktop)
    api(files("libs/android-jar-1.0.0.jar"))
    /*
    api(files("libs/android-appcompat.jar"))
    api(files("libs/android-appcompat-extra.jar"))
    api(files("libs/android-core.jar"))
    api(files("libs/android-fragment.jar"))
    api(files("libs/android-activity.jar"))
    api(files("libs/android-lifecycle.jar"))
    api(files("libs/android-lifecycle-viewmodel.jar"))
    api(files("libs/android-savedata.jar"))
    */

    compileOnly(commonDesktopLib.android.annotations)
    compileOnly(commonDesktopLib.xmlpull)
}



