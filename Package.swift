// swift-tools-version: 6.2
// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import PackageDescription

let package = Package(
    name: "spfk-metadata-image",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "SPFKMetadataImage",
            targets: ["SPFKMetadataImage"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ryanfrancesconi/spfk-base", from: "1.2.3"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-testing", from: "1.1.0"),
        // Test-only: libwebp's muxer is the oracle for the WebP chunk splice.
        .package(url: "https://github.com/ryanfrancesconi/spfk-webp", from: "0.1.3"),
    ],
    targets: [
        .target(
            name: "SPFKMetadataImage",
            dependencies: [
                .product(name: "SPFKBase", package: "spfk-base"),
            ]
        ),
        .testTarget(
            name: "SPFKMetadataImageTests",
            dependencies: [
                "SPFKMetadataImage",
                .product(name: "SPFKBase", package: "spfk-base"),
                .product(name: "SPFKTesting", package: "spfk-testing"),
                .product(name: "libwebp", package: "spfk-webp"),
            ]
        ),
    ]
)
