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
        .library(name: "EncoCore", targets: ["EncoCore"])
    ],
    targets: [
        .executableTarget(name: "EncoProbe"),
        .target(name: "EncoCore"),
        .executableTarget(name: "EncoCLI", dependencies: ["EncoCore"], linkerSettings: [
            .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist])
        ]),
        .executableTarget(name: "EncoChecks", dependencies: ["EncoCore"], path: "Tests/EncoCoreTests")
    ]
)
