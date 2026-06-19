import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.objectweb.asm.ClassReader

plugins {
    alias(libs.plugins.kotlin.jvm)
}

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
    api(projects.libraries.common)
    api(commonLib.bundles.common)
}
