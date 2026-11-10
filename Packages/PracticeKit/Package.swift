// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PracticeKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // 节奏设置值类型，App 的节拍引擎也直接用这个库。
        .library(name: "RhythmKit", targets: ["RhythmKit"]),
        // 歌单 / 训练 / 练习统计。会 re-export RhythmKit。
        .library(name: "PracticeKit", targets: ["PracticeKit"]),
    ],
    targets: [
        .target(name: "RhythmKit"),
        .target(name: "PracticeKit", dependencies: ["RhythmKit"]),
        .testTarget(name: "RhythmKitTests", dependencies: ["RhythmKit"]),
        .testTarget(name: "PracticeKitTests", dependencies: ["PracticeKit"]),
    ]
)
