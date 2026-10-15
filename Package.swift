// swift-tools-version: 5.9
import PackageDescription
import Foundation

let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Support/Info.plist").path

let package = Package(
    name: "EncoAir5Pro",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "enco-probe", targets: ["EncoProbe"]),
        .executable(name: "enco", targets: ["EncoCLI"]),
        .executable(name: "enco-menu", targets: ["EncoMenu"]),
        .library(name: "EncoCore", targets: ["EncoCore"])
    ],
    targets: [
        .executableTarget(name: "EncoProbe"),
        .target(name: "EncoCore"),
        .binaryTarget(name: "Sparkle", url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-for-Swift-Package-Manager.zip", checksum: "17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959"),
        .executableTarget(name: "EncoMenu", dependencies: ["EncoCore", "Sparkle"], resources: [.process("Resources")]),
        .executableTarget(name: "EncoCLI", dependencies: ["EncoCore"], linkerSettings: [
            .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist])
        ]),
        .executableTarget(name: "EncoChecks", dependencies: ["EncoCore"], path: "Tests/EncoCoreTests")
    ]
)
