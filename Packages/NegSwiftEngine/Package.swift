// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NegSwiftEngine",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "NegSwiftEngine", targets: ["NegSwiftEngine"]),
        .executable(name: "negswift-engine-swift", targets: ["negswift-engine-swift"]),
    ],
    targets: [
        .target(
            name: "NegSwiftEngine",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "negswift-engine-swift",
            dependencies: ["NegSwiftEngine"]
        ),
        .testTarget(
            name: "NegSwiftEngineTests",
            dependencies: ["NegSwiftEngine"]
        ),
    ]
)
