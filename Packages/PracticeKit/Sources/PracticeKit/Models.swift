import Foundation
import SwiftData

// 模型按 CloudKit 同步的要求写：所有属性都有默认值、没有 unique 约束。
// 以后用 CloudKit 同步练习记录时不用改模型。

@Model
public final class PracticeSession {
    public var id: UUID = UUID()
    public var startedAt: Date = Date()
    /// 实际播放时长，单位秒。
    public var duration: TimeInterval = 0
    public var minBPM: Int = Tempo.default
    public var maxBPM: Int = Tempo.default
    public var modeRaw: String = PracticeMode.free.rawValue

    public init(
        startedAt: Date,
        duration: TimeInterval,
        minBPM: Int,
        maxBPM: Int,
        mode: PracticeMode = .free
    ) {
        self.startedAt = startedAt
        self.duration = duration
        self.minBPM = min(minBPM, maxBPM)
        self.maxBPM = max(minBPM, maxBPM)
        self.modeRaw = mode.rawValue
    }

    public var mode: PracticeMode {
        get { PracticeMode(rawValue: modeRaw) ?? .free }
        set { modeRaw = newValue.rawValue }
    }

    public var bpmRange: ClosedRange<Int> { minBPM...maxBPM }

    public var endedAt: Date { startedAt.addingTimeInterval(duration) }
}

/// 创建 ModelContainer 时用的模型列表。App 如果有自己的 Schema，把它并进去即可。
public enum PracticeKitSchema {
    public static var models: [any PersistentModel.Type] {
        [PracticeSession.self]
    }

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
        )
    }
}
