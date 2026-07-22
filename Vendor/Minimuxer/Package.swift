// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Minimuxer",
    platforms: [
        .iOS(.v16),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "Minimuxer",
            targets: ["Minimuxer"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "RustBridgeLib",
            path: "RustBridge/lib/RustBridge.xcframework"
        ),
        .target(
            name: "RustBridge",
            dependencies: ["RustBridgeLib"],
            path: "RustBridge",
            exclude: [
                "Cargo.toml",
                "Cargo.lock",
                "src",
                "Makefile",
                "lib"
            ],
            sources: ["MinimuxerBridgeIdevice.swift"]
        ),
        .target(
            name: "Minimuxer",
            dependencies: ["RustBridge"],
            path: "Sources"
        )
    ]
)
