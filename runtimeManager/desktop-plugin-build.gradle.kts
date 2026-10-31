import java.util.zip.ZipFile
import org.gradle.api.artifacts.ResolvedDependency
import org.gradle.api.file.FileTreeElement
import org.gradle.api.specs.Spec

val coreLibraries = configurations.create("desktopCoreLibraries") {
    isCanBeConsumed = false
    isCanBeResolved = true
    attributes {
        attribute(Usage.USAGE_ATTRIBUTE, objects.named(Usage.JAVA_RUNTIME))
    }
}

dependencies {
    add(coreLibraries.name, project(":libraries:commonDesktopLib"))
}

fun ResolvedDependency.module() = "$moduleGroup:$moduleName"

fun collect(into: MutableMap<String, String>, dependency: ResolvedDependency) {
    if (into.put(dependency.module(), dependency.moduleVersion) == null) {
        dependency.children.forEach { collect(into, it) }
    }
}

val coreVersions: Map<String, String> by lazy {
    val versions = linkedMapOf<String, String>()
    coreLibraries.resolvedConfiguration.lenientConfiguration.firstLevelModuleDependencies
        .forEach { collect(versions, it) }
    versions
}

// shadow's types are not visible to an applied script, so the project's shadowJar block takes these from extra
extra["desktopCoreShared"] = Spec<ResolvedDependency> {
    coreVersions[it.module()] == it.moduleVersion
}

val coreEntries: Set<String> by lazy {
    val names = hashSetOf<String>()
    coreLibraries.files.filter { it.extension == "jar" }.forEach { jar ->
        ZipFile(jar).use { zip ->
            zip.entries().asSequence().filter { !it.isDirectory }.forEach { names.add(it.name) }
        }
    }
    names
}
extra["desktopCoreEntry"] = Spec<FileTreeElement> {
    !it.isDirectory &&
        !it.relativePath.pathString.startsWith("META-INF/") &&
        it.relativePath.pathString in coreEntries
}
// the core is first on the classpath, so a different version of a shared library would silently win
extra["desktopCoreCheck"] = Action<Task> {
    val mine = linkedMapOf<String, String>()
    configurations.getByName("runtimeClasspath").resolvedConfiguration
        .lenientConfiguration.firstLevelModuleDependencies
        .forEach { collect(mine, it) }
    val clashes = mine.filter { (module, version) ->
        coreVersions[module]?.let { it != version } == true
    }
    if (clashes.isNotEmpty()) {
        throw GradleException(
            "[${project.name}] resolves libraries at a different version than desktopCore: " +
                clashes.entries.joinToString { "${it.key} ${it.value} (core ${coreVersions[it.key]})" } +
                ". Align the versions so the backend can use the shared copy.",
        )
    }
}
