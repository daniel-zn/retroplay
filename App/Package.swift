// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "RetroPlay",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "RetroPlayCore", targets: ["RetroPlayCore"]),
        .library(name: "RetroPlayApp", targets: ["RetroPlayApp"]),
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
