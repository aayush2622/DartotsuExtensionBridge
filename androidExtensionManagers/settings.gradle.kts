@file:Suppress("UnstableApiUsage")

rootProject.name = "dartotsu_aniyomi_plugin"

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io")

    }
}
include(":common")
include(":aniyomi")
include(":cloudStream")

include(":bridgetest")
