// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MisarDev",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "MisarDev",
            targets: ["MisarDev"]
        ),
    ],
    targets: [
        .target(
            name: "MisarDev",
            path: "Sources/MisarDev"
        ),
        .testTarget(
            name: "MisarDevTests",
            dependencies: ["MisarDev"],
            path: "Tests/MisarDevTests"
        ),
    ]
)
