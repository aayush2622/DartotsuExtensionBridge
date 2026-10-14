// swift-tools-version: 5.9
import PackageDescription

// SwiftPM resolves both binary frameworks itself, so a plain
// `flutter build ios` needs no prepare script.
//
// OpenJDKRuntime.xcframework is committed as a zip (Frameworks/ios-runtime-v1),
// built by ../PrepareEmbeddedRuntime.sh. To change it, rebuild it with that
// script, zip the xcframework (`ditto -c -k --sequesterRsrc --keepParent`) and
// commit it under a new Frameworks/ios-runtime-vN folder.
//
// TorrServerKit.xcframework is TorrServer's own iOS release asset, the same
// file ../PrepareTorrServerRuntime.sh downloads, pinned by checksum.
//
// The Runtime/ folder (embedded-bridge.jar, logging shim, cacerts) and the
// jdk/ headers are committed; the CocoaPods path still regenerates them.
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
            path: "Frameworks/ios-runtime-v1/OpenJDKRuntime.xcframework.zip"
        ),
        .binaryTarget(
            name: "TorrServerKit",
            url: "https://github.com/YouROK/TorrServer/releases/download/MatriX.146.1/TorrServer-ios-TorrServerKit.xcframework.zip",
            checksum: "20d0f1e705f72cc87209330570b058eb6368a8800a4ad7cc694802b11b9a2700"
        ),
        .target(
            name: "dartotsu_embedded_jvm",
            dependencies: ["OpenJDKRuntime"],
            resources: [
                .copy("Runtime"),
            ],
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("jdk"),
            ]
        ),
        .target(
            name: "dartotsu_extension_bridge",
            dependencies: ["dartotsu_embedded_jvm", "TorrServerKit"],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
    ],
    cxxLanguageStandard: .gnucxx20
)
