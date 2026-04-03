import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import proguard.gradle.ProGuardTask

buildscript {
    repositories {
        mavenCentral()
    }
    dependencies {
        classpath("com.guardsquare:proguard-gradle:7.9.0")
    }
}

plugins {
    alias(aniyomiDesktop.plugins.kotlin.jvm)
    alias(aniyomiDesktop.plugins.shadow)
    alias(aniyomiDesktop.plugins.kotlin.serialization)

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
    implementation(aniyomiDesktop.bundles.common)
    implementation(aniyomiDesktop.okio)
    implementation(aniyomiDesktop.bundles.settings)

    implementation(aniyomiDesktop.bundles.okhttp)
    implementation(aniyomiDesktop.asm)

    implementation(aniyomiDesktop.serialization.xml.core)
    implementation(aniyomiDesktop.serialization.xml)

    implementation(aniyomiDesktop.bundles.polyglot)

    implementation(aniyomiDesktop.injekt)
    implementation(aniyomiDesktop.rxjava)
    implementation(aniyomiDesktop.jsoup)

    implementation(aniyomiDesktop.bundles.javalin)
    implementation(aniyomiDesktop.bundles.jackson)

    compileOnly(aniyomiDesktop.apksig)
    compileOnly(aniyomiDesktop.android.annotations)
    compileOnly(aniyomiDesktop.xmlpull)

    implementation("com.google.code.gson:gson:2.13.2")
    implementation(files("libs/android-jar-1.0.0.jar"))

    implementation(project(":common"))
}

tasks.shadowJar {
    archiveClassifier.set("all")


    exclude(
        "META-INF/**",
        "**/*.pom",
    )

    mergeServiceFiles()
    isZip64 = true
}

tasks.register<ProGuardTask>("proguard") {

    configuration(file("proguard.pro"))

    injars(tasks.shadowJar.get().archiveFile)

    val javaHome = System.getProperty("java.home")

    if (System.getProperty("java.version").startsWith("1.")) {
        libraryjars("$javaHome/lib/rt.jar")
    } else {
        libraryjars(
            mapOf(
                "jarfilter" to "!**.jar",
                "filter" to "!module-info.class"
            ),
            "$javaHome/jmods/java.base.jmod"
        )
    }

    verbose()

    outjars(layout.buildDirectory.file("../../builds/aniyomiDesktop/aniyomiDesktop.jar"))
}

tasks.build {
    dependsOn("proguard")
}
tasks.jar {
    enabled = false
}
artifacts {
    add("shadow", tasks.shadowJar)
}