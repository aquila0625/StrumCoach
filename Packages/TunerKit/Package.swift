// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TunerKit",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TunerKit", targets: ["TunerKit"]),
    ],
    targets: [
        .target(name: "TunerKit", resources: [.process("Resources"), .copy("Samples")]),
        .testTarget(name: "TunerKitTests", dependencies: ["TunerKit"]),
    ]
)
