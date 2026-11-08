import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.android.kmp.library)
    alias(libs.plugins.kotlin.serialization)

}

// Tsuki ships its own copy of org.koitharu.kotatsu.core.parser.CSSBackground,
// which this module also vendors for Kotatsu parser jars; two copies cannot
// both go into the Android dex, so the vendored one stays and Tsuki's is cut.
val tsukiRaw: Configuration by configurations.creating { isTransitive = false }
dependencies { tsukiRaw("com.github.UsagiApp:Tsuki:1.0.5") }
val tsukiStripped = tasks.register<Jar>("tsukiStripped") {
    archiveFileName.set("tsuki-stripped.jar")
    destinationDirectory.set(layout.buildDirectory.dir("tsuki"))
    from({ zipTree(tsukiRaw.singleFile) })
    exclude("org/koitharu/**")
}

kotlin {
    jvm("desktop")
    android {
        compileSdk = libs.versions.compileSdk.get().toInt()
        minSdk = libs.versions.minSdk.get().toInt()
        namespace = "com.aayush262.kotatsu.shared"
    }
    sourceSets {
        getByName("androidMain") {
            dependencies {
                api(projects.libraries.commonLib)
                api("uy.kohesive.injekt:injekt-core:1.16.1")
            }
        }

        getByName("commonMain") {
            dependencies {
                val isAndroidBuild = gradle.startParameter.taskNames.any {
                    it.contains("android", true)

                }
                implementation("androidx.collection:collection:1.6.0")
                implementation(files(tsukiStripped))
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
                implementation("org.jsoup:jsoup:1.17.2")

                if (!isAndroidBuild) {
                    compileOnly(projects.libraries.commonDesktopLib)
                }
            }
        }

        getByName("desktopMain") {
            dependencies {
                api(projects.libraries.commonDesktopLib)
            }
        }
    }

    jvmToolchain(libs.versions.java.get().toInt())

    compilerOptions {
        freeCompilerArgs.addAll(
            "-Xexpect-actual-classes",
            "-Xannotation-default-target=param-property",
            "-opt-in=kotlin.RequiresOptIn",
            "-opt-in=kotlin.contracts.ExperimentalContracts",
            "-opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi",
            "-opt-in=org.koitharu.kotatsu.parsers.InternalParsersApi",
            "-opt-in=tsuki.InternalParsersApi"
        )

    }
}