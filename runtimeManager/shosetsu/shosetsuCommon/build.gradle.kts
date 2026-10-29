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
        namespace = "com.aayush262.shosetsu.shared"
    }
    sourceSets {
        getByName("commonMain") {
            dependencies {
                api(projects.libraries.commonLib)
                implementation("org.luaj:luaj-jse:3.0.1")
                implementation("com.google.guava:guava:33.5.0-jre")
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")

                val isAndroidBuild = gradle.startParameter.taskNames.any {
                    it.contains("android", true)
                }

                if (!isAndroidBuild) {
                    compileOnly(projects.libraries.commonDesktopLib)
                }
            }
        }

        getByName("androidMain") {
            dependencies {
                api(projects.libraries.commonLib)
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
        )
    }
}
