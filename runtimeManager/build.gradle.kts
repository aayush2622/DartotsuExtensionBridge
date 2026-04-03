plugins {
    id("com.android.library") version "8.10.0" apply false
    id("com.android.application") version "8.10.0" apply false
    kotlin("android") version "2.1.0" apply false
    alias(aniyomiDesktop.plugins.kotlin.jvm) apply false
    alias(aniyomiDesktop.plugins.shadow) apply false
    alias(aniyomiDesktop.plugins.kotlin.serialization) apply false
}

tasks.register<Delete>("clean") {
    delete(layout.buildDirectory)
}

