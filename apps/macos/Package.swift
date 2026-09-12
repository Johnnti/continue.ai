// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ContinueMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ContinueCore", targets: ["ContinueCore"]),
        .executable(name: "ContinueApp", targets: ["ContinueApp"]),
        .executable(name: "ContinueControlExtension", targets: ["ContinueControlExtension"]),
        .executable(name: "ContinueCoreChecks", targets: ["ContinueCoreChecks"])
    ],
    targets: [
        .target(
            name: "ContinueCore",
            path: "Sources/ContinueCore",
            resources: [
                .copy("Resources/Contracts")
            ]
        ),
        .executableTarget(
            name: "ContinueApp",
            dependencies: ["ContinueCore"],
            path: "Sources/ContinueApp"
        ),
        .executableTarget(
            name: "ContinueControlExtension",
            path: "Sources/ContinueControlExtension"
        ),
        .executableTarget(
            name: "ContinueCoreChecks",
            dependencies: ["ContinueCore"],
            path: "Tests/ContinueCoreChecks",
            sources: ["main.swift"]
        )
    ]
)
