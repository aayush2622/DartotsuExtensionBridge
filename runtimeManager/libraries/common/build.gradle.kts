plugins {
    id("org.jetbrains.kotlin.jvm")
}
// cant use lib here because it is also imported by core project
group = "com.aayush262.dartotsu_extension_bridge"
version = "1.0"

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}