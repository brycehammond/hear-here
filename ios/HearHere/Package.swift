// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HearHere",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "HearHere",
            targets: ["HearHere"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/AzureAD/microsoft-authentication-library-for-objc.git",
            from: "1.5.0"
        ),
    ],
    targets: [
        .target(
            name: "HearHere",
            dependencies: [
                .product(name: "MSAL", package: "microsoft-authentication-library-for-objc"),
            ],
            path: ".",
            exclude: ["Package.swift", "Tests"],
            resources: [
                .process("Resources/Assets.xcassets"),
            ]
        ),
        .testTarget(
            name: "HearHereTests",
            dependencies: ["HearHere"],
            path: "Tests"
        ),
    ]
)
