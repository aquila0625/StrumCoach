// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MetronomeCore",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MetronomeCore", targets: ["MetronomeCore"]),
    ],
    dependencies: [
        // 拍号、重音、切分（RhythmKit）和训练方案（PracticeKit）的唯一来源
        .package(path: "../../Packages/PracticeKit"),
    ],
    targets: [
        .target(name: "MetronomeCore", dependencies: [.product(name: "PracticeKit", package: "PracticeKit")],
                resources: [.process("Resources")]),
        .testTarget(name: "MetronomeCoreTests", dependencies: ["MetronomeCore"]),
    ]
)
