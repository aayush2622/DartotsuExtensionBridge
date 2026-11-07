import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

val upstreamRepo = "https://github.com/recloudstream/cloudstream.git"
val upstreamSha = "5024ace2922a148d38df2a816b483b529789cf58"
val upstreamPatchRev = "1"
val upstreamDir = layout.buildDirectory.dir("cloudstream-upstream")
val upstreamSrc = upstreamDir.map { it.dir("library/src") }

val syncCloudStreamLibrary = tasks.register("syncCloudStreamLibrary") {
    val dir = upstreamDir.get().asFile
    val stamp = File(dir, ".sha")
    outputs.file(stamp)
    doLast {
        val expected = "$upstreamSha+$upstreamPatchRev"
        if (stamp.exists() && stamp.readText().trim() == expected) return@doLast
        dir.deleteRecursively()
        dir.mkdirs()
        fun git(vararg args: String) {
            val process = ProcessBuilder("git", *args).directory(dir).redirectErrorStream(true).start()
            val output = process.inputStream.bufferedReader().readText()
            if (process.waitFor() != 0) throw GradleException("git ${args.joinToString(" ")} failed:\n$output")
        }
        git("init", "-q")
        git("remote", "add", "origin", upstreamRepo)
        git("config", "core.sparseCheckout", "true")
        File(dir, ".git/info/sparse-checkout").apply { parentFile.mkdirs() }.writeText("library/src/\n")
        git("fetch", "-q", "--depth", "1", "origin", upstreamSha)
        git("checkout", "-q", "FETCH_HEAD")
        File(dir, "generated/com/lagradost/api").mkdirs()
        File(dir, "generated/com/lagradost/api/BuildConfig.kt").writeText(
            """
            package com.lagradost.api

            object BuildConfig {
                const val MDL_API_KEY: String = ""
                const val TRAKT_CLIENT_ID: String = ""
            }
            """.trimIndent() + "\n"
        )
        val mainApi = File(dir, "library/src/commonMain/kotlin/com/lagradost/cloudstream3/MainAPI.kt")
        val dateFormat = "                val fmt = DateTimeComponents.Format { byUnicodePattern(format) }\n"
        val source = mainApi.readText()
        if (!source.contains(dateFormat)) throw GradleException("MainAPI.addDate changed upstream; update the month-name patch")
        mainApi.writeText(
            source.replace(
                dateFormat,
                "                if (format.contains(\"MMM\")) return@getOrElse bridgeParseNamedMonth(date, format)\n" + dateFormat,
            ) + """

internal fun bridgeParseNamedMonth(date: String, format: String): Long =
    java.text.SimpleDateFormat(format, java.util.Locale.ENGLISH).parse(date.trim())!!.time
""",
        )
        stamp.writeText(expected)
    }
}

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.android.kmp.library)
    alias(libs.plugins.kotlin.serialization)

}

kotlin {
    jvm("desktop")
    android {
        compileSdk = libs.versions.compileSdk.get().toInt()
        minSdk = libs.versions.minSdk.get().toInt()
        namespace = "com.aayush262.cloudStream.shared"
    }
    sourceSets {
        all {
            languageSettings {
                optIn("com.lagradost.cloudstream3.InternalAPI")
                optIn("com.lagradost.cloudstream3.Prerelease")
            }
        }

        val jvmCommonMain = create("jvmCommonMain") {
            dependsOn(getByName("commonMain"))
            kotlin.srcDir(upstreamSrc.map { it.dir("jvmCommonMain/kotlin") })
            dependencies {
                api(cloudStreamCommon.kotlin.reflect)
            }
        }

        getByName("androidMain") {
            dependsOn(jvmCommonMain)
            kotlin.srcDir(upstreamSrc.map { it.dir("androidMain/kotlin") })
            dependencies {
                api(projects.libraries.commonLib)
                api(cloudStreamCommon.preference.ktx)
            }
        }

        getByName("commonMain") {
            kotlin.srcDir(upstreamSrc.map { it.dir("commonMain/kotlin") })
            kotlin.srcDir(upstreamDir.map { it.dir("generated") })
            dependencies {
                api(cloudStreamCommon.bundles.common)
                val isAndroidBuild = gradle.startParameter.taskNames.any {
                    it.contains("android", true)

                }

                if (!isAndroidBuild) {
                    compileOnly(projects.libraries.commonDesktopLib)
                }
            }
        }

        getByName("desktopMain") {
            dependsOn(jvmCommonMain)
            kotlin.srcDir(upstreamSrc.map { it.dir("androidMain/kotlin") })
            dependencies{
                api(projects.libraries.commonDesktopLib)
                api(cloudStreamCommon.ksoup.jvm)
            }
        }
    }

    jvmToolchain( libs.versions.java.get().toInt())

    compilerOptions {
        freeCompilerArgs.addAll("-Xexpect-actual-classes")

    }
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompilationTask<*>>().configureEach {
    dependsOn(syncCloudStreamLibrary)
}
