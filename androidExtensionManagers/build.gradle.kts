plugins {
    id("com.android.application") version "8.10.0" apply false
    kotlin("android") version "2.2.10" apply false
    kotlin("plugin.serialization") version "2.0.21" apply false
}

tasks.register<Delete>("clean") {
    delete(layout.buildDirectory)
}