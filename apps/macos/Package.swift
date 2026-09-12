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
    dependencies: [
        .package(
            url: "https://github.com/elevenlabs/elevenlabs-swift-sdk.git",
            exact: "3.3.1"
        )
    ],
    targets: [
        .target(
            name: "ContinueCore",
            path: "Sources/ContinueCore",
            resources: [
                .copy("Resources/Contracts")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "ContinueApp",
            dependencies: [
                "ContinueCore",
                .product(name: "ElevenLabs", package: "elevenlabs-swift-sdk")
            ],
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
            sources: ["main.swift"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
