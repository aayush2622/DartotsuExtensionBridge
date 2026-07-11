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
        namespace = "com.aayush262.aniyomi.shared"
    }
    sourceSets {
        getByName("androidMain") {
            dependencies {
                api(projects.libraries.commonLib)
                api(aniyomiAndroid.bundles.android)

            }
        }

        getByName("commonMain") {
            dependencies {
                api(aniyomiCommon.bundles.common)
                val isAndroidBuild = gradle.startParameter.taskNames.any {
                    it.contains("Android", ignoreCase = true)
                }
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

    jvmToolchain( libs.versions.java.get().toInt())
    compilerOptions {
        freeCompilerArgs.addAll("-Xcontext-parameters","-Xexpect-actual-classes")

    }
}
