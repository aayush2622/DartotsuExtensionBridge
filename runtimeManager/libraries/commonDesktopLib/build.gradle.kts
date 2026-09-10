import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.shadow)
}

group = "com.aayush262"
version = "1.0"

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

dependencies {
    api(projects.libraries.commonLib)
    api(commonDesktopLib.bundles.desktop)
    api(files("libs/android-jar-1.0.0.jar"))
    /*
    api(files("libs/android-appcompat.jar"))
    api(files("libs/android-appcompat-extra.jar"))
    api(files("libs/android-core.jar"))
    api(files("libs/android-fragment.jar"))
    api(files("libs/android-activity.jar"))
    api(files("libs/android-lifecycle.jar"))
    api(files("libs/android-lifecycle-viewmodel.jar"))
    api(files("libs/android-savedata.jar"))
    */

    compileOnly(commonDesktopLib.android.annotations)
    compileOnly(commonDesktopLib.xmlpull)
}

/*
 * The iOS embedded OpenJDK Zero VM is created with only this slim JAR on
 * `-Djava.class.path` (see ios/PrepareEmbeddedRuntime.sh). It must carry
 * `EmbeddedBridge` / `Server` / `ChildFirstURLClassLoader` / `ExtensionApi`
 * plus gson + kotlin/coroutines, and NOT the desktop extension runtime
 * (dex2jar, JCEF, GraalVM, apk-parser, icu4j, …) — every backend fat JAR
 * ships its own and the child-first loader must win.
 *
 *   ./gradlew :libraries:commonDesktopLib:embeddedBridgeJar
 *     -> libraries/commonDesktopLib/build/libs/embedded-bridge.jar
 */
tasks.shadowJar {
    archiveBaseName.set("embedded-bridge")
    archiveClassifier.set("")
    archiveVersion.set("")
    dependencies {
        exclude(dependency("org.jetbrains.intellij.deps.jcef:.*:.*"))
        exclude(dependency("org.jogamp.jogl:.*:.*"))
        exclude(dependency("org.jogamp.gluegen:.*:.*"))
        exclude(dependency("net.java.dev.jna:.*:.*"))
        exclude(dependency("de.femtopedia.dex2jar:.*:.*"))
        exclude(dependency("org.graalvm.*:.*:.*"))
        exclude(dependency("net.dongliu:apk-parser:.*"))
        exclude(dependency("com.ibm.icu:.*:.*"))
        exclude(dependency("com.fasterxml.jackson.*:.*:.*"))
        exclude(dependency("io.reactivex:rxjava:.*"))
        exclude(dependency("org.ow2.asm:.*:.*"))
        exclude(dependency("com.russhwolf:.*:.*"))
        exclude(dependency("io.github.pdvrieze.xmlutil:.*:.*"))
    }
    exclude(
        "org/cef/**", "org/jogamp/**", "com/jogamp/**", "jogamp/**",
        "com/sun/jna/**", "native/**", "jni/**",
        "**/*.dll", "**/*.dylib", "**/*.so", "**/*.jnilib",
        "META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA",
    )
    mergeServiceFiles()
}

tasks.register("embeddedBridgeJar") {
    group = "plugin"
    description = "Slim JAR the iOS embedded VM boots with (EmbeddedBridge on the classpath)."
    dependsOn(tasks.shadowJar)
}



