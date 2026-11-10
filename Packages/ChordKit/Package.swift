// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChordKit",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ChordKit", targets: ["ChordKit"]),
    ],
    dependencies: [
        .package(path: "../TunerKit"),
    ],
    targets: [
        .target(name: "ChordKit", dependencies: [.product(name: "TunerKit", package: "TunerKit")], resources: [.process("Resources")]),
        .testTarget(name: "ChordKitTests", dependencies: [
            "ChordKit", .product(name: "TunerKit", package: "TunerKit"),
        ]),
    ]
)
