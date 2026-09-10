# iOS embedded-JVM support — what's scaffolded and what's left

On iOS the four `*Desktop` backends can't run as a `java -jar` subprocess and
can't JIT. Instead the plugin embeds an **interpreter-only OpenJDK Zero VM**
in-process (native side under `ios/`, Dart side
`lib/Engines/JavaEngine/Bridge/EmbeddedJvmBridge.dart`). The approach — a
static OpenJDK framework `dlopen`ed lazily, a dedicated JVM-sized bootstrap
thread, Serial GC, `-Xss8m` — is copied from
<https://github.com/kodjodevf/m_extension_server>.

## Done in this repo

- `commonDesktopLib`:
  - `Server.kt` — the request `when(method)` block is extracted into
    `Server.handle(api, method, params)`; `Server.run` (the desktop stdio
    loop) is unchanged behaviourally.
  - `EmbeddedBridge.kt` — `object` with `@JvmStatic load(jarPath)`,
    `call(jarPath, requestJson)`, `unload(jarPath)`, `pause()`, `resume()`.
    `load` attaches the backend fat JAR in a `ChildFirstURLClassLoader`,
    reflectively calls `Main.api()`, caches it. `call` runs
    `Server.handle(...)` and returns a `{"success":…,"data"|"error":…}`
    envelope. The native layer (`ios/Classes/EmbeddedJvm.mm`) looks this class
    up as `com/aayush262/dartotsu_extension_bridge/EmbeddedBridge` and calls
    those exact signatures.
- Each `*ExtensionCli.kt` `Main` gained `@JvmStatic fun api(): ExtensionApi`
  (desktop `main` now calls it too).

## Left to do (needs a macOS + the Gradle build)

### 1. Build the `embedded-bridge.jar` shim

The embedded VM is created with **only this jar** on `-Djava.class.path`
(`ios/PrepareEmbeddedRuntime.sh` stages it as `Runtime/embedded-bridge.jar`).
It must contain, and only contain:

- `com.aayush262.dartotsu_extension_bridge.**` from `commonLib` +
  `commonDesktopLib` (`EmbeddedBridge`, `Server`, `ExtensionApi`,
  `ExtensionBridgeApi`, `ChildFirstURLClassLoader`, …)
- `com.google.gson.**`
- `kotlin-stdlib` + `kotlinx-coroutines-core`

It must **not** contain the backend runtimes (okhttp, kcef, tachiyomi,
android-compat shims) — every backend fat JAR ships its own and the
child-first loader must win. A `shadowJar` with `dependencies { … }` narrowed
to the four artifacts above, or an explicit `include(...)` filter, does it.

Sketch (new `commonDesktopLib` task):

```kotlin
tasks.register<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar>("embeddedBridgeJar") {
    archiveFileName.set("embedded-bridge.jar")
    from(sourceSets.main.get().output)
    configurations = listOf(project.configurations.runtimeClasspath.get())
    dependencies {
        include(dependency("com.google.code.gson:gson"))
        include(dependency("org.jetbrains.kotlin:kotlin-stdlib.*"))
        include(dependency("org.jetbrains.kotlinx:kotlinx-coroutines-core.*"))
    }
    exclude("META-INF/**")
}
```

### 2. Build iOS-flavoured backend JARs

The current `*Desktop-plugin.jar`s assume a desktop JVM (kcef/CEF webview, AWT
`Robot`, `ProcessBuilder`). For iOS Zero:

- exclude kcef / CEF and any `java.awt.*` usage (guard `CloudflareInterceptor`
  and friends behind a capability check that returns "unsupported" instead of
  loading CEF);
- keep everything else — okhttp, jsoup, the android-compat shims, gson all run
  fine under Zero.

Produce e.g. `aniyomiDesktop-plugin-ios.jar` per backend.

### 3. Publish + wire `plugins.json`

Add an iOS row per backend, e.g.

```json
{
  "name": "aniyomiDesktop",
  "platform": "ios",
  "type": "jar",
  "fileName": "aniyomiDesktop-plugin-ios.jar",
  "downloadUrl": "https://github.com/aayush2622/DartotsuExtensionBridge/releases/download/latest/aniyomiDesktop-plugin-ios.jar"
}
```

`DownloadablePlugin` already resolves the row by `name` + platform; on iOS it
should pick the `ios` row. `EmbeddedJvmBridge` then feeds that jar path to
`load` / `call`.

### 4. Publish the pinned shim jar (optional)

`ios/PrepareEmbeddedRuntime.sh` will download `embedded-bridge.jar` from
`BRIDGE_JAR_URL` (with a real SHA-256) if it isn't already at
`ios/Runtime/embedded-bridge.jar`. Either publish it to the
`embedded-ios-v1` release and fill in `BRIDGE_JAR_SHA256`, or commit the jar
under `ios/Runtime/` and leave the download unused.
