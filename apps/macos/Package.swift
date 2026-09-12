// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ContinueMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ContinueApp", targets: ["ContinueApp"])
    ],
    targets: [
        .executableTarget(
            name: "ContinueApp",
            path: "Sources/ContinueApp"
        )
    ]
)
