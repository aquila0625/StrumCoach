import Foundation

/// 渐进提速：从起始 BPM 出发，每 `barsPerStep` 小节增加 `step`，直到目标 BPM。
/// 目标低于起始时是渐进减速。所有函数都是纯函数，小节序号 `bar` 从 0 开始（第 0 小节是第一小节）。
public struct RampSettings: Codable, Hashable, Sendable {
    public enum EndBehavior: String, Codable, CaseIterable, Sendable {
        /// 目标速度那一档播完后停止。
        case stop
        /// 到目标后一直保持目标速度。
        case hold
        /// 目标速度那一档播完后回到起始 BPM，重新爬。
        case loop
    }

    public let startBPM: Int
    public let targetBPM: Int
    /// 每档变化的 BPM，恒为正数；方向由起止决定。
    public let step: Int
    /// 每档持续的小节数，至少 1。
    public let barsPerStep: Int
    public let endBehavior: EndBehavior

    /// 非法参数会被修正：BPM 夹到 `Tempo.range`，`step` 和 `barsPerStep` 至少为 1。
    public init(startBPM: Int, targetBPM: Int, step: Int, barsPerStep: Int, endBehavior: EndBehavior = .hold) {
        self.startBPM = Tempo.clamp(startBPM)
        self.targetBPM = Tempo.clamp(targetBPM)
        self.step = max(1, step)
        self.barsPerStep = max(1, barsPerStep)
        self.endBehavior = endBehavior
    }

    private enum CodingKeys: String, CodingKey { case startBPM, targetBPM, step, barsPerStep, endBehavior }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            startBPM: try c.decode(Int.self, forKey: .startBPM),
            targetBPM: try c.decode(Int.self, forKey: .targetBPM),
            step: try c.decode(Int.self, forKey: .step),
            barsPerStep: try c.decode(Int.self, forKey: .barsPerStep),
            endBehavior: try c.decodeIfPresent(EndBehavior.self, forKey: .endBehavior) ?? .hold
        )
    }

    public var isAscending: Bool { targetBPM >= startBPM }

    /// 从起始到目标要走几档（最后一档不足一个 `step` 时直接落到目标）。
    public var stepCount: Int {
        let distance = abs(targetBPM - startBPM)
        return (distance + step - 1) / step
    }

    /// 目标速度出现的第一个小节序号。
    public var barsToTarget: Int { stepCount * barsPerStep }

    /// 目标速度那一档播完的小节序号：`stop` 在这里结束，`loop` 在这里回到起点。
    public var cycleBars: Int { (stepCount + 1) * barsPerStep }

    /// 第 `bar` 小节所在的档位（0 = 起始速度）。`loop` 时按周期折回。
    public func stepIndex(atBar bar: Int) -> Int {
        var b = max(0, bar)
        if endBehavior == .loop { b %= cycleBars }
        return min(b / barsPerStep, stepCount)
    }

    /// 第 `bar` 小节的 BPM。
    public func bpm(atBar bar: Int) -> Int {
        let travelled = min(stepIndex(atBar: bar) * step, abs(targetBPM - startBPM))
        return isAscending ? startBPM + travelled : startBPM - travelled
    }

    /// 进度 0...1：已走档数 / 总档数。起止相同（0 档）时恒为 1。
    public func progress(atBar bar: Int) -> Double {
        guard stepCount > 0 else { return 1 }
        return Double(stepIndex(atBar: bar)) / Double(stepCount)
    }

    /// 只有 `stop` 会结束：目标速度那一档播完后返回 true。
    public func isFinished(atBar bar: Int) -> Bool {
        endBehavior == .stop && max(0, bar) >= cycleBars
    }
}
