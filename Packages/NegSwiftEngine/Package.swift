// swift-tools-version: 6.0

import Foundation
import PackageDescription

/// Homebrew / pkg-config LibRaw on macOS. `NEGSWIFT_LIBRAW=0` forces the stub so
/// `swift test` still builds when headers are absent (S14 optional target).
func librawPrefix() -> String? {
    if ProcessInfo.processInfo.environment["NEGSWIFT_LIBRAW"] == "0" {
        return nil
    }
    func hasHeader(_ prefix: String) -> Bool {
        FileManager.default.fileExists(atPath: "\(prefix)/include/libraw/libraw.h")
    }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["brew", "--prefix", "libraw"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    do {
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let prefix = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                hasHeader(prefix)
            {
                return prefix
            }
        }
    } catch {}
    for prefix in ["/opt/homebrew/opt/libraw", "/usr/local/opt/libraw"] {
        if hasHeader(prefix) { return prefix }
    }
    return nil
}

let librawHome = librawPrefix()
let librawCSettings: [CSetting] = {
    guard let prefix = librawHome else { return [] }
    return [
        .define("NEGSWIFT_HAS_LIBRAW", .when(platforms: [.macOS])),
        .unsafeFlags(["-I\(prefix)/include"], .when(platforms: [.macOS])),
    ]
}()
let librawLinkerSettings: [LinkerSetting] = {
    var settings: [LinkerSetting] = [
        .linkedFramework("Accelerate"),
    ]
    guard let prefix = librawHome else { return settings }
    settings.append(
        .unsafeFlags(
            ["-L\(prefix)/lib", "-lraw_r", "-Xlinker", "-rpath", "-Xlinker", "\(prefix)/lib"],
            .when(platforms: [.macOS])
        )
    )
    return settings
}()

let package = Package(
    name: "NegSwiftEngine",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "NegSwiftEngine", targets: ["NegSwiftEngine"]),
        .executable(name: "negswift-engine-swift", targets: ["negswift-engine-swift"]),
    ],
    targets: [
        .target(
            name: "NegSwiftLibRaw",
            publicHeadersPath: "include",
            cSettings: librawCSettings,
            linkerSettings: librawLinkerSettings
        ),
        .target(
            name: "NegSwiftEngine",
            dependencies: ["NegSwiftLibRaw"],
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
