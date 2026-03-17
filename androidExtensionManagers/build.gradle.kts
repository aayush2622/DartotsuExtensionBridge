plugins {
    id("com.android.library") version "8.10.0" apply false
    id("com.android.application") version "8.10.0" apply false
    kotlin("android") version "2.2.0" apply false
    kotlin("plugin.serialization") version "2.2.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.10" apply false
}

tasks.register<Delete>("clean") {
    delete(layout.buildDirectory)
}