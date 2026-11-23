// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "RetroPlay",
    platforms: [
        // The app ships for iOS 26 (project.yml): its navigation-bar title and subtitle places.
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "RetroPlayCore", targets: ["RetroPlayCore"]),
        .library(name: "RetroPlayApp", targets: ["RetroPlayApp"]),
    ],
    dependencies: [
        // Unpacks the zipped copy iOS gives of a folder it lists as empty (a network share's).
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.21"),
    ],
    targets: [
        .target(
            name: "RetroPlayCore",
            dependencies: ["ZIPFoundation"],
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
