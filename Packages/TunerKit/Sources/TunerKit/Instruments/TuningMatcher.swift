import Foundation

/// 把检测到的音高对到目标音（某根弦，或半音阶里最近的半音）。
public struct TuningResult: Equatable, Sendable {
    public let reading: PitchReading
    /// 目标音；半音阶模式下就是最近的半音。
    public let target: Pitch
    /// 目标是哪根弦（半音阶模式为 nil）。
    public let stringIndex: Int?
    /// 相对目标音的偏差（音分）。可能远超 ±50（例如手动锁定了别的弦）。
    public let cents: Double
    public let targetFrequency: Double

    public var isInTune: Bool { abs(cents) <= TunerDefaults.inTuneCents }
    public var isFlat: Bool { cents < -TunerDefaults.inTuneCents }
    public var isSharp: Bool { cents > TunerDefaults.inTuneCents }
}

extension Tuning {
    /// 离给定频率最近的一根弦（按音分距离，对回弦定弦同样有效）。
    public func closestString(toFrequency frequency: Double,
                              a4: Double = TunerDefaults.a4) -> (string: InstrumentString, cents: Double)? {
        guard frequency > 0 else { return nil }
        var best: (InstrumentString, Double)?
        for s in strings {
            let c = Pitch.cents(from: s.pitch.frequency(a4: a4), to: frequency)
            if best == nil || abs(c) < abs(best!.1) { best = (s, c) }
        }
        return best.map { (string: $0.0, cents: $0.1) }
    }

    /// 为一次检测结果找目标。
    /// - Parameter lockedString: 手动锁定的弦；为 nil 时自动选最近的弦。
    public func match(_ reading: PitchReading, lockedString: Int? = nil) -> TuningResult {
        let a4 = reading.a4
        if isChromatic {
            let p = reading.pitch
            return TuningResult(reading: reading, target: p, stringIndex: nil,
                                cents: reading.cents, targetFrequency: p.frequency(a4: a4))
        }
        if let lockedString, strings.indices.contains(lockedString) {
            let s = strings[lockedString]
            let f = s.pitch.frequency(a4: a4)
            return TuningResult(reading: reading, target: s.pitch, stringIndex: s.index,
                                cents: Pitch.cents(from: f, to: reading.frequency), targetFrequency: f)
        }
        let (s, c) = closestString(toFrequency: reading.frequency, a4: a4)!
        return TuningResult(reading: reading, target: s.pitch, stringIndex: s.index,
                            cents: c, targetFrequency: s.pitch.frequency(a4: a4))
    }
}
