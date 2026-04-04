import org.jetbrains.kotlin.gradle.dsl.JvmTarget


plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.shadow)
    alias(libs.plugins.kotlin.serialization)

}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
        freeCompilerArgs.add("-Xcontext-receivers")
    }
}

dependencies {
    implementation(aniyomiCommon.okhttp)
    implementation(aniyomiCommon.okhttp.logging)
    implementation(aniyomiCommon.okhttp.doh)
    implementation(aniyomiCommon.okhttp.brotli)

    implementation(aniyomiCommon.okio)

    implementation(aniyomiCommon.rxjava)
    implementation(aniyomiCommon.jsoup)

    implementation(aniyomiCommon.coroutines.core)

    implementation(aniyomiCommon.serialization.json)
    implementation(aniyomiCommon.serialization.json.okio)
    implementation(aniyomiCommon.serialization.protobuf)
    implementation(aniyomiCommon.gson)


    implementation(aniyomiDesktop.bundles.common)
    implementation(aniyomiDesktop.bundles.settings)
    implementation(aniyomiDesktop.asm)
    implementation(aniyomiDesktop.bundles.xml)
    implementation(aniyomiDesktop.bundles.polyglot)
    implementation(aniyomiDesktop.bundles.javalin)
    implementation(aniyomiDesktop.bundles.jackson)
    implementation(aniyomiDesktop.injekt)
    compileOnly(aniyomiDesktop.apksig)
    compileOnly(aniyomiDesktop.android.annotations)
    compileOnly(aniyomiDesktop.xmlpull)

    implementation(files("libs/android-jar-1.0.0.jar"))

    implementation(project(":common"))
}

tasks.shadowJar {
    archiveClassifier.set("all")
    exclude(
        "META-INF/**",
        "**/*.pom",
        "**/*.pom.*"
    )

    mergeServiceFiles()
    isZip64 = true
}

apply(from = "$rootDir/plugin-build.gradle.kts")

tasks.build {
    dependsOn(tasks.shadowJar)
}

tasks.jar {
    enabled = false
}