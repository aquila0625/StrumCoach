import Foundation

/// 判定“某个音调准了”：偏差持续在准音区内一段时间才算，且同一个音只提示一次。
///
/// - 目标音（弦、或半音阶模式下的音名）的偏差**连续** `holdSeconds`（默认 0.5 秒）都在 ±`tuneCents`（默认 ±5 音分）以内，才触发一次 `.tuned`；
/// - 触发后这个音被“锁住”，不会再提示；偏出 ±`rearmCents`（默认 ±10 音分）时解锁（给 `.drifted`），再回到准音区才会再次提示；
/// - 目标换了、信号丢了、偏差超出准音区，持续时间都从头算。
///
/// 纯逻辑、不碰音频，时间由调用方传入，所以可以在测试里精确地推进。
public struct TuneConfirmation: Sendable {
    public enum Event: Equatable, Sendable {
        /// 这个音刚刚调准。
        case tuned(Int)
        /// 这个音（已调准过）偏出了解锁范围，可以再次提示。
        case drifted(Int)
    }

    public var holdSeconds: Double
    public var tuneCents: Double
    public var rearmCents: Double

    private var holdKey: Int?
    private var holdStart: TimeInterval = 0
    private var latched: Set<Int> = []

    public init(holdSeconds: Double = 0.5, tuneCents: Double = TunerDefaults.inTuneCents, rearmCents: Double = 10) {
        self.holdSeconds = holdSeconds
        self.tuneCents = tuneCents
        self.rearmCents = rearmCents
    }

    public func isLatched(_ key: Int) -> Bool { latched.contains(key) }

    public mutating func reset() {
        holdKey = nil
        latched.removeAll()
    }

    /// 只清掉“正在计时”的状态，保留已提示过的音（例如暂停检测之后继续）。
    public mutating func restartHold() { holdKey = nil }

    /// 喂入一次结果。`key` 是目标音的标识（弦的序号，或半音阶下的 MIDI 号），`cents` 是相对目标的偏差；没有信号时两者都传 nil。
    public mutating func update(key: Int?, cents: Double?, now: TimeInterval) -> Event? {
        guard let key, let cents else { holdKey = nil; return nil }
        let deviation = abs(cents)

        var event: Event?
        if deviation > rearmCents, latched.remove(key) != nil { event = .drifted(key) }

        guard deviation <= tuneCents else { holdKey = nil; return event }
        if holdKey != key { holdKey = key; holdStart = now }
        if !latched.contains(key), now - holdStart >= holdSeconds {
            latched.insert(key)
            return .tuned(key)
        }
        return event
    }
}
