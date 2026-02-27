// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftMTP",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SwiftMTP", targets: ["SwiftMTP"]),
    ],
    targets: [
        .systemLibrary(
            name: "Clibmtp",
            pkgConfig: "libmtp",
            providers: [.brew(["libmtp"])]
        ),
        .target(
            name: "SwiftMTP",
            dependencies: ["Clibmtp"]
        ),
        .testTarget(
            name: "SwiftMTPTests",
            dependencies: ["SwiftMTP"]
        ),
    ]
)
