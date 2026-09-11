// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dartotsu_extension_bridge",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "dartotsu-extension-bridge", targets: ["dartotsu_extension_bridge"])
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "OpenJDKRuntime",
            path: "Frameworks/OpenJDKRuntime.xcframework"
        ),
        .target(
            name: "dartotsu_extension_bridge",
            dependencies: ["OpenJDKRuntime"],
            resources: [
                .copy("Runtime"),
                .process("PrivacyInfo.xcprivacy"),
            ],
            cSettings: [
                .headerSearchPath("include/dartotsu_extension_bridge")
            ]
        ),
    ],
    cxxLanguageStandard: .gnucxx20
)
