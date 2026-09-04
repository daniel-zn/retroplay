// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RetroPlay",
    platforms: [
        .iOS(.v18) // Raise to iOS 26 when Xcode SDK available; Liquid Glass requires 26 at runtime
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
    ]
)
