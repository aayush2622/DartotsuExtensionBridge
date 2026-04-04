@file:Suppress("UnstableApiUsage")

rootProject.name = "DartotsuRuntimePlugins"

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
        maven("https://jogamp.org/deployment/maven")
    }
    versionCatalogs {
        create("aniyomiDesktop") {
            from(files("gradle/aniyomiDesktop-lib.toml"))
        }
        create("aniyomiCommon") {
            from(files("gradle/aniyomiCommon-lib.toml"))
        }
        create("aniyomiAndroid") {
            from(files("gradle/aniyomiAndroid-lib.toml"))
        }
        create("libs") {
            from(files("gradle/libs.version.toml"))
        }
    }
}


include(":common")
include(":aniyomiAndroid")
include(":aniyomiDesktop")
include(":cloudStream")
