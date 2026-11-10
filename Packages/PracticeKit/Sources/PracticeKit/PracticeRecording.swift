import Foundation
import SwiftData

/// 练习记录的入库规则。
public enum PracticeRecording {
    /// 少于这个时长（秒）的播放不记录。刚好 30 秒算有效。
    public static let minimumDuration: TimeInterval = 30

    public static func shouldRecord(duration: TimeInterval) -> Bool {
        duration >= minimumDuration
    }

    /// 停止播放时调用。时长不足 30 秒返回 nil 且不写入；否则插入 `context` 并返回记录（不自动 save）。
    @discardableResult
    public static func record(
        startedAt: Date,
        duration: TimeInterval,
        bpmRange: ClosedRange<Int>,
        mode: PracticeMode,
        in context: ModelContext
    ) -> PracticeSession? {
        guard shouldRecord(duration: duration) else { return nil }
        let session = PracticeSession(
            startedAt: startedAt, duration: duration,
            minBPM: bpmRange.lowerBound, maxBPM: bpmRange.upperBound,
            mode: mode
        )
        context.insert(session)
        return session
    }
}
