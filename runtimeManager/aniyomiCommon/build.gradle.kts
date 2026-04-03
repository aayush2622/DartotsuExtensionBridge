plugins {
    alias(aniyomiDesktop.plugins.kotlin.jvm)
    kotlin("plugin.serialization")
}
kotlin {
    jvmToolchain(17)
    compilerOptions {
        freeCompilerArgs.add("-Xcontext-receivers")

    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
dependencies {
    implementation("uy.kohesive.injekt:injekt-core:1.16.1")


    implementation("org.jsoup:jsoup:1.21.1")

    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json-okio:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-protobuf:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")

    implementation("com.squareup.okhttp3:okhttp:5.0.0-alpha.14")
    implementation("com.squareup.okhttp3:logging-interceptor:5.0.0-alpha.14")
    implementation("com.squareup.okhttp3:okhttp-dnsoverhttps:5.0.0-alpha.14")
    implementation("com.squareup.okhttp3:okhttp-brotli:5.0.0-alpha.14")

    implementation("com.squareup.okio:okio:3.8.0")
    implementation("io.reactivex:rxjava:1.3.8")
    implementation("io.reactivex:rxandroid:1.2.1")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")


    compileOnly(project(":common"))

    implementation("org.apache.commons:commons-text:1.11.0")
}