@file:Suppress("UnstableApiUsage")




enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")
rootProject.name = "DartotsuRuntimePlugins"

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()

    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)

    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io")
        maven("https://jogamp.org/deployment/maven")
        maven("https://packages.jetbrains.team/maven/p/ij/intellij-dependencies")
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
        create("commonLib") {
            from(files("libraries/commonLib/libs/common-lib.toml"))
        }
        create("commonDesktopLib") {
            from(files("libraries/commonDesktopLib/libs/commonDesktop-lib.toml"))
        }
        create("aniyomiCommon") {
            from(files("aniyomi/aniyomiCommon/libs/aniyomiCommon-lib.toml"))
        }
        create("aniyomiAndroid") {
            from(files("aniyomi/aniyomiCommon/libs/aniyomiAndroid-lib.toml"))
        }
        create("cloudStreamCommon") {
            from(files("cloudStream/cloudStreamCommon/libs/cloudStreamCommon-lib.toml"))
        }
        create("ireaderCommon") {
            from(files("ireader/ireaderCommon/libs/ireaderCommon-lib.toml"))
        }
        create("libs") {
            from(files("gradle/libs.version.toml"))
        }
    }
}


include(
    ":libraries:common",
    ":libraries:commonLib",
    ":libraries:commonDesktopLib",
    ":aniyomi:aniyomiCommon",
    ":aniyomi:aniyomiAndroid",
    ":aniyomi:aniyomiDesktop",
    ":cloudStream:cloudStreamCommon",
    ":cloudStream:cloudStreamAndroid",
    ":cloudStream:cloudStreamDesktop",
    ":kotatsu:kotatsuCommon",
    ":kotatsu:kotatsuAndroid",
    ":kotatsu:kotatsuDesktop",
    ":ireader:ireaderCommon",
    ":ireader:ireaderAndroid",
    ":ireader:ireaderDesktop",
    ":tsundoku:tsundokuCommon",
    ":tsundoku:tsundokuAndroid",
    ":tsundoku:tsundokuDesktop",
)
