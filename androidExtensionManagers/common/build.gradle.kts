plugins {
    kotlin("jvm")
}

group = "com.aayush262.dartotsu_extension_bridge"
version = "1.0"

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}