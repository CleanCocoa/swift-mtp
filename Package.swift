// swift-tools-version: 6.2
import PackageDescription

#if os(macOS)
let linkerSettings: [LinkerSetting] = [.unsafeFlags(["-L/opt/homebrew/lib"])]
#else
let linkerSettings: [LinkerSetting] = []
#endif

let package = Package(
    name: "SwiftMTP",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SwiftMTP", targets: ["SwiftMTP"]),
        .library(name: "SwiftMTPAsync", targets: ["SwiftMTPAsync"]),
    ],
    targets: [
        .systemLibrary(
            name: "Clibmtp",
            pkgConfig: "libmtp",
            providers: [.brew(["libmtp"]), .apt(["libmtp-dev"])]
        ),
        .target(
            name: "MTPCore",
            dependencies: ["Clibmtp"],
            linkerSettings: linkerSettings
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
