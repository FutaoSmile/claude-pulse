// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCLight",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cc-light", targets: ["CCLight"])
    ],
    targets: [
        .executableTarget(
            name: "CCLight",
            path: "Sources/CCLight",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
