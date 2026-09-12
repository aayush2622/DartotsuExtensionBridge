import org.gradle.internal.os.OperatingSystem
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.net.URI
import java.security.MessageDigest
import java.util.zip.ZipFile

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

// TorrServer's binary is baked into jniLibs at build time rather than
// downloaded at Dart runtime like the desktop TorrServerAddon: a
// runtime-downloaded file generally can't be marked executable and exec'd on
// modern Android (W^X / SELinux `noexec` on writable app-data partitions),
// but files under the APK's nativeLibraryDir are granted exec permission by
// PackageManager at install time.
val downloadTorrServerBinaries = tasks.register("downloadTorrServerBinaries") {
    // Config-cache can't serialize references to the build script object, so
    // every value the `doLast` action touches is captured here as a plain,
    // serializable value (String/Map) rather than via Project DSL helpers
    // (`file()`, `copy {}`, `zipTree()`) resolved through the script's
    // implicit receiver - see `buildCommonJar` above for the same pattern.
    val version = "0.0.6"
    val jniDirPath = file("src/main/jniLibs").absolutePath
    val abis = mapOf(
        "arm64-v8a" to "torrserver-android-arm64",
        "x86_64" to "torrserver-android-amd64",
        "armeabi-v7a" to "torrserver-android-arm7",
        "x86" to "torrserver-android-386",
    )

    outputs.files(abis.keys.map { File("$jniDirPath/$it/libtorrserver.so") })

    doLast {
        fun extractSingleEntry(zip: File, dest: File) {
            ZipFile(zip).use { zf ->
                val entry = zf.entries().asSequence().first { !it.isDirectory }
                zf.getInputStream(entry).use { input ->
                    dest.outputStream().use { input.copyTo(it) }
                }
            }
        }

        val jniDir = File(jniDirPath)
        val localBin = System.getenv("TORRSERVER_LOCAL_BINARIES")
        val versionMarker = File(jniDir, ".version")

        if (versionMarker.exists() && versionMarker.readText().trim() != version) {
            println("TorrServer version changed to $version. Cleaning stale jniLibs...")
            jniDir.deleteRecursively()
        }

        val checksums = mutableMapOf<String, String>()
        if (localBin == null) {
            runCatching {
                val url =
                    "https://github.com/ayman708-UX/torrserver_flutter/releases/download/v$version/checksums.txt"
                URI(url).toURL().readText().lineSequence().forEach { line ->
                    val parts = line.trim().split(Regex("\\s+"))
                    if (parts.size >= 2) {
                        checksums[parts[1].trimStart('*', '/')] = parts[0]
                    }
                }
            }.onFailure {
                println("Note: checksums.txt fetch deferred: ${it.message}")
            }
        }

        abis.forEach { (abi, binName) ->
            val abiDir = File(jniDir, abi).apply { mkdirs() }
            val target = File(abiDir, "libtorrserver.so")
            val zipName = "$binName.zip"

            if (target.exists()) return@forEach

            val localZip = localBin?.let { File(it, zipName) }
            val localBinary = localBin?.let { File(it, binName) }

            when {
                localZip != null && localZip.exists() -> {
                    println("Extracting local TorrServer archive for $abi from $localBin")
                    extractSingleEntry(localZip, target)
                }

                localBinary != null && localBinary.exists() -> {
                    println("Copying local TorrServer binary for $abi from $localBin")
                    localBinary.copyTo(target, overwrite = true)
                }

                else -> {
                    println("Downloading TorrServer binary for $abi (v$version)...")
                    runCatching {
                        val url =
                            "https://github.com/ayman708-UX/torrserver_flutter/releases/download/v$version/$zipName"
                        val tempZip = File(abiDir, "temp_$zipName")
                        URI(url).toURL().openStream().use { input ->
                            tempZip.outputStream().use { input.copyTo(it) }
                        }

                        checksums[zipName]?.let { expected ->
                            val digest = MessageDigest.getInstance("SHA-256")
                            tempZip.forEachBlock(4096) { buffer, bytesRead ->
                                digest.update(buffer, 0, bytesRead)
                            }
                            val actual = digest.digest().joinToString("") { "%02x".format(it) }
                            if (!actual.equals(expected, ignoreCase = true)) {
                                tempZip.delete()
                                throw GradleException(
                                    "SHA-256 mismatch for $zipName! expected=$expected actual=$actual",
                                )
                            }
                            println("Verified SHA-256 for $zipName")
                        }

                        extractSingleEntry(tempZip, target)
                        tempZip.delete()
                    }.onFailure {
                        println("Warning: failed to download TorrServer binary for $abi: ${it.message}")
                    }
                }
            }

            if (target.exists()) {
                target.setExecutable(true, false)
                target.setReadable(true, false)
            }
        }

        versionMarker.parentFile.mkdirs()
        versionMarker.writeText(version)
    }
}

tasks.named("preBuild") {
    dependsOn(downloadTorrServerBinaries)
}
