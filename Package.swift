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
                .product(name: "SPFKTesting", package: "spfk-testing"),
            ]
        ),
    ]
)
