// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftMTP",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SwiftMTP", targets: ["SwiftMTP"]),
        .library(name: "SwiftMTPAsync", targets: ["SwiftMTPAsync"]),
    ],
    targets: [
        .systemLibrary(
            name: "Clibmtp",
            pkgConfig: "libmtp",
            providers: [.brew(["libmtp"])]
        ),
        .target(
            name: "MTPCore",
            dependencies: ["Clibmtp"],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib"])
            ]
        ),
        .target(
            name: "SwiftMTP",
            dependencies: ["MTPCore"]
        ),
        .target(
            name: "SwiftMTPAsync",
            dependencies: ["MTPCore"]
        ),
        .testTarget(
            name: "MTPCoreTests",
            dependencies: ["MTPCore"]
        ),
        .testTarget(
            name: "HardwareTests",
            dependencies: ["SwiftMTPAsync"]
        ),
    ]
)
