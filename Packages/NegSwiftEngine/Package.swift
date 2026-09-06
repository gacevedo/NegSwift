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
            resources: [.process("Resources")],
            swiftSettings: [
                // Local package only — Xcode rejects unsafeFlags on remote deps.
                // Debug -Onone is ~9 min for a 45 MP export; -O is ~25 s.
                .unsafeFlags(["-O"], .when(configuration: .debug)),
            ]
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
