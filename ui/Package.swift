// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LoomModules",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "UI", targets: ["UI"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "App", targets: ["App"])
    ],
    targets: [
        .target(name: "Core"),
        .target(
            name: "UI",
            dependencies: ["Core"]
        ),
        .target(
            name: "Networking",
            dependencies: ["Core"]
        ),
        .target(
            name: "App",
            dependencies: ["Core", "Networking", "UI"]
        )
    ]
)
