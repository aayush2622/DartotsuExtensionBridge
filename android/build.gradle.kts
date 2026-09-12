import org.gradle.internal.os.OperatingSystem
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library") version "9.2.1"
    id("org.jetbrains.kotlin.plugin.serialization") version "2.3.21"
}

group = "com.aayush262.dartotsu_extension_bridge"
version = "1.0-SNAPSHOT"

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
        maven {
            url = uri("http://download.flutter.io")
            isAllowInsecureProtocol = true
        }
    }
}

android {
    namespace = "com.aayush262.dartotsu_extension_bridge"

    compileSdk = 37
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 21
        consumerProguardFiles("proguard-rules.pro")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

configurations.configureEach {
    exclude(group = "org.json", module = "json")
}

val runtimeManagerDir = file("../runtimeManager")
val commonJar = file("../runtimeManager/libraries/common/build/libs/common-1.0.jar")

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json-okio:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-protobuf:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    implementation("org.jetbrains.kotlin:kotlin-reflect:2.2.0")
    implementation("com.squareup.okio:okio:3.16.4")
    implementation(files(commonJar))

    compileOnly("io.flutter:flutter_embedding_debug:1.0.0-ef0cd000916d64fa0c5d09cc809fa7ad244a5767")
}

val buildCommonJar = tasks.register<Exec>("buildCommonJar") {
    // onlyIf's predicate is retained for the configuration cache, which can't
    // serialize a reference to the build script itself - capture the path as
    // a plain local String rather than closing over the script-level
    // `commonJar` property.
    val commonJarPath = commonJar.absolutePath

    outputs.file(commonJar)

    commandLine(
        File(
            runtimeManagerDir,
            if (OperatingSystem.current().isWindows) "gradlew.bat" else "gradlew",
        ).absolutePath,
        "-p",
        runtimeManagerDir.absolutePath,
        ":libraries:common:jar",
    )

    onlyIf {
        !File(commonJarPath).exists()
    }
}

tasks.configureEach {
    if (name.startsWith("compile") || name == "preBuild") {
        dependsOn(buildCommonJar)
    }
}
