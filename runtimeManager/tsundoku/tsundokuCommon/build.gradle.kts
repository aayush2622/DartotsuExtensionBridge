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
        namespace = "com.aayush262.tsundoku.shared"
    }
    sourceSets {
        getByName("androidMain") {
            dependencies {
                api(projects.libraries.commonLib)
            }
        }

        getByName("commonMain") {
            dependencies {
                val isAndroidBuild = gradle.startParameter.taskNames.any {
                    it.contains("android", true)

                }
                implementation(projects.aniyomi.aniyomiCommon)
                if (!isAndroidBuild) {
                    compileOnly(projects.libraries.commonDesktopLib)
                }
            }
        }

        getByName("desktopMain") {
            dependencies{
                api(projects.libraries.commonDesktopLib)

            }
        }
    }
    sourceSets {
        commonMain {
            kotlin.srcDir("src/commonMain/kotlin")
            kotlin.exclude("**/AniyomiExtensionApi.kt")
        }
    }
    jvmToolchain( 21)

    compilerOptions {
        freeCompilerArgs.addAll("-XXLanguage:+NestedTypeAliases","-Xexpect-actual-classes","-Xannotation-default-target=param-property")

    }
}
java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(21))
    }
}
