import com.android.build.gradle.internal.tasks.factory.dependsOn
import com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar
import org.gradle.api.artifacts.ResolvedDependency
import org.gradle.api.file.FileTreeElement
import org.gradle.api.specs.Spec

extra.apply {
    set("pluginRequires", listOf("desktopCore"))
    set("pluginAuthor", "aayush262/Ryan")
    set("pluginDescription", "A plugin that allows you to run cloudstream extensions on desktop")
}
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.shadow)
}

dependencies {
    implementation(projects.cloudStream.cloudStreamCommon)
}

apply(from = "$rootDir/desktop-plugin-build.gradle.kts")

@Suppress("UNCHECKED_CAST")
val sharedDependency = project.extra["desktopCoreShared"] as Spec<ResolvedDependency>

@Suppress("UNCHECKED_CAST")
val sharedEntry = project.extra["desktopCoreEntry"] as Spec<FileTreeElement>

@Suppress("UNCHECKED_CAST")
val sharedCheck = project.extra["desktopCoreCheck"] as Action<Task>

tasks.shadowJar {
    archiveClassifier.set("all")
    dependencies { exclude(sharedDependency) }
    exclude(sharedEntry)
    exclude("**/*.pom", "**/*.pom.*")
    manifest {
        attributes("Main-Class" to "com.aayush262.dartotsu_extension_bridge.Main")
    }
    mergeServiceFiles()
    isZip64 = true
    isReproducibleFileOrder = true
    isPreserveFileTimestamps = false
    doFirst(sharedCheck)
}

tasks.register<ShadowJar>("fatJar") {
    group = "shadow"
    archiveClassifier.set("fat")
    from(sourceSets.main.get().output)
    configurations = listOf(project.configurations.runtimeClasspath.get())
    exclude("**/*.pom", "**/*.pom.*")
    manifest {
        attributes("Main-Class" to "com.aayush262.dartotsu_extension_bridge.Main")
    }
    mergeServiceFiles()
    isZip64 = true
    isReproducibleFileOrder = true
    isPreserveFileTimestamps = false
}

apply(from = "$rootDir/plugin-build.gradle.kts")

tasks.jar { enabled = false }

tasks.build.dependsOn(tasks.shadowJar)
