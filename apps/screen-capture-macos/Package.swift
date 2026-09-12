// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContinueScreenCapture",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "continue-screen-capture", targets: ["ContinueScreenCapture"])
    ],
    targets: [
        .executableTarget(name: "ContinueScreenCapture")
    ]
)
