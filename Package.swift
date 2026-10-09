// swift-tools-version: 5.10
import Foundation
import PackageDescription

// Official builds add the private Pro module in Pro/ (ignored by git). Builds from source don't need it.
// SwiftPM caches this check: after you add or remove Pro/, build once with --manifest-cache none.
let hasPro = FileManager.default.fileExists(atPath: Context.packageDirectory + "/Pro/Sources/VibemetricPro")

let package = Package(
    name: "Vibemetric",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VibemetricApp", targets: ["VibemetricApp"]),
        .executable(name: "vibemetric", targets: ["vibemetric"]),
        .library(name: "VibemetricCore", targets: ["VibemetricCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(name: "VibemetricCore", resources: [.copy("Resources/rubric.md")]),
        .executableTarget(name: "vibemetric", dependencies: ["VibemetricCore"]),
        // The app is a library so other modules can import its types; VibemetricApp only launches it.
        .target(name: "VibemetricAppKit", dependencies: ["VibemetricCore", .product(name: "Sparkle", package: "Sparkle")],
                resources: [.copy("Resources/Brand")]),
        .executableTarget(
            name: "VibemetricApp",
            dependencies: ["VibemetricAppKit"] + (hasPro ? ["VibemetricPro"] : []),
            // A flag, not canImport: a stale VibemetricPro module in .build would otherwise still match.
            swiftSettings: hasPro ? [.define("VIBEMETRIC_PRO")] : []
        ),
        .testTarget(name: "VibemetricCoreTests", dependencies: ["VibemetricCore"]),
        .testTarget(name: "VibemetricAppTests", dependencies: ["VibemetricAppKit"]),
    ] + (hasPro ? [
        .target(name: "VibemetricPro", dependencies: ["VibemetricAppKit"], path: "Pro/Sources/VibemetricPro"),
        .testTarget(name: "VibemetricProTests", dependencies: ["VibemetricPro"], path: "Pro/Tests/VibemetricProTests"),
    ] : [])
)
