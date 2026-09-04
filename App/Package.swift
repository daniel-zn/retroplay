// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RetroPlay",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(name: "RetroPlayCore", targets: ["RetroPlayCore"]),
    ],
    targets: [
        .target(
            name: "RetroPlayCore",
            path: "Sources/RetroPlayCore"
        ),
        .target(
            name: "RetroPlayApp",
            dependencies: ["RetroPlayCore"],
            path: "Sources/RetroPlayApp"
        ),
        .testTarget(
            name: "RetroPlayCoreTests",
            dependencies: ["RetroPlayCore"],
            path: "Tests/RetroPlayCoreTests"
        ),
    ]
)
