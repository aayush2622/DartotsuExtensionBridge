import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

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
                // The real, published library - not vendored source. Our own
                // hand-vendored copy of its core (MangaParser/AbstractMangaParser/...)
                // generalized `source: MangaParserSource` (a KSP-generated, 1000+-entry
                // enum) down to a hand-written `MangaSource` interface, which changes
                // the compiled `getSource()` method descriptor. A real, currently
                // published parsers jar's site classes are compiled against the real
                // interface, so loading them against our vendored one throws
                // AbstractMethodError/IncompatibleClassChangeError for effectively
                // every source - depending on the real artifact instead means our own
                // code and any same-version repo jar agree on the exact same classes.
                implementation("com.github.KotatsuApp:kotatsu-parsers:1.7")

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
            "-opt-in=org.koitharu.kotatsu.parsers.InternalParsersApi"
        )

    }
}