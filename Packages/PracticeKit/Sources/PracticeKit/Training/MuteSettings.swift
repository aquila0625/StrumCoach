import Foundation

/// 静音训练：训练“自己心里的拍子”。
public struct MuteSettings: Codable, Hashable, Sendable {
    public enum Pattern: Codable, Hashable, Sendable {
        /// 有声 `audible` 小节，接着静音 `muted` 小节，循环。
        case bars(audible: Int, muted: Int)
        /// 每一拍以 `probability`（0...1）的概率静音。同一个种子永远得到同一个结果，可以复现。
        case randomBeats(probability: Double, seed: UInt64)
    }

    public var pattern: Pattern
    /// 仅对随机静音有效：每小节第一拍永远有声。
    public var keepsDownbeat: Bool

    public init(pattern: Pattern, keepsDownbeat: Bool = false) {
        self.pattern = pattern
        self.keepsDownbeat = keepsDownbeat
    }

    public static func bars(audible: Int, muted: Int) -> MuteSettings {
        MuteSettings(pattern: .bars(audible: audible, muted: muted))
    }

    public static func randomBeats(probability: Double, seed: UInt64, keepsDownbeat: Bool = false) -> MuteSettings {
        MuteSettings(pattern: .randomBeats(probability: probability, seed: seed), keepsDownbeat: keepsDownbeat)
    }

    /// 第 `bar` 小节的第 `beat` 拍是否静音（都从 0 开始，负数按 0 处理）。
    /// `bars` 模式下，`audible` 至少按 1 算，`muted` 小于 0 按 0 算。
    public func isMuted(bar: Int, beat: Int) -> Bool {
        let bar = max(0, bar)
        let beat = max(0, beat)
        switch pattern {
        case let .bars(audible, muted):
            let on = max(1, audible)
            let off = max(0, muted)
            return bar % (on + off) >= on
        case let .randomBeats(probability, seed):
            if keepsDownbeat && beat == 0 { return false }
            let p = min(max(probability, 0), 1)
            let h = Self.mix(Self.mix(Self.mix(seed) ^ UInt64(bar)) ^ UInt64(beat))
            let unit = Double(h >> 11) / Double(1 << 53)  // [0, 1)
            return unit < p
        }
    }

    /// SplitMix64 的混合函数。
    private static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
