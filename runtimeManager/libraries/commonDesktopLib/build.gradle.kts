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
 * `-Djava.class.path` (see ios/PrepareEmbeddedRuntime.sh). Its ONLY job is to
 * host `EmbeddedBridge`, which loads each backend fat JAR in an isolated
 * URLClassLoader parented to the platform loader (JDK only) and reflects into
 * `Main.handle`. Nothing crosses that boundary but `java.lang.String`, so the
 * shim needs nothing beyond `EmbeddedBridge` + kotlin-stdlib — no gson, no
 * coroutines, no `Server`, no `ExtensionApi`, no extension runtime.
 *
 *   ./gradlew :libraries:commonDesktopLib:embeddedBridgeJar
 *     -> libraries/commonDesktopLib/build/libs/embedded-bridge.jar
 */
tasks.shadowJar {
    archiveBaseName.set("embedded-bridge")
    archiveClassifier.set("")
    archiveVersion.set("")
    // Only EmbeddedBridge itself + the kotlin runtime it is compiled against.
    include("com/aayush262/dartotsu_extension_bridge/EmbeddedBridge*.class")
    include("kotlin/**")
    include("META-INF/*.kotlin_module")
    include("META-INF/versions/**/kotlin/**")
    mergeServiceFiles()
}

tasks.register("embeddedBridgeJar") {
    group = "plugin"
    description = "Slim JAR the iOS embedded VM boots with (EmbeddedBridge on the classpath)."
    dependsOn(tasks.shadowJar)
}



