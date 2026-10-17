// swift-tools-version:5.9
//
// This manifest exists for the PUBLIC MIRROR repository
// (github.com/Misar-AI/misardev-sdks), not for this monorepo.
//
// Swift Package Manager requires Package.swift at the repository ROOT and has
// no notion of a package living in a subdirectory — so the mirror's root
// manifest reaches down into swift/ for its sources. That is also why the Swift
// SDK cannot be consumed from this repo directly at any path.
//
// sdks/swift/Package.swift remains the local manifest, used for building and
// testing the SDK in place; this one is copied to the mirror root by
// .forgejo/workflows/sync-sdks-to-github.yml. Both must describe the same
// targets — if you add one here, add it there.

import PackageDescription

let package = Package(
    name: "MisarDev",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v8)],
    products: [
        .library(name: "MisarDev", targets: ["MisarDev"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MisarDev",
            path: "swift/Sources/MisarDev"
        ),
        .testTarget(
            name: "MisarDevTests",
            dependencies: ["MisarDev"],
            path: "swift/Tests/MisarDevTests"
        ),
    ]
)
